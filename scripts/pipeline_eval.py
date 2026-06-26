#!/usr/bin/env python3
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Agent evaluation using Amazon Bedrock AgentCore On-Demand Evaluations.

Single entry point for both CI/CD and local dev. Uses the bedrock-agentcore
EvaluationClient SDK which handles Amazon CloudWatch span download and evaluation
orchestration internally.

Flow:
  1. Invoke agent with eval cases (generates OTel traces)
  2. Wait for CloudWatch span ingestion
  3. Call EvaluationClient.run() with ground-truth references
  4. Aggregate scores, publish metrics, pass/fail on threshold

Eval case discovery:
  --eval-cases-dir loads every *.yaml and *.json in the directory (and
  globs **/*.yaml for nested files). Keeps scenarios co-located with the
  agent and lets teams split cases by concern (regression, safety, …).

Scenario schema (YAML or JSON):
  cases:                      # optional wrapper; bare list also accepted
    - name: "Tool usage"
      prompt: "How many words in 'hello world'?"
      assertions:
        - "Agent used a tool"
        - "Agent returned correct count of 2"
      trajectory:
        - "gateway_tool-target___text_analysis_tool"
      expected_response: null  # optional

Usage:
    # Pipeline (Secrets Manager auth, headless)
    python3 scripts/pipeline_eval.py \\
        --runtime-arn <arn> --region eu-west-1 \\
        --agent-name basic-agent \\
        --eval-cases-dir agents/basic-agent/eval

    # Local dev (interactive Cognito login)
    python3 scripts/pipeline_eval.py \\
        --runtime-arn <arn> --region eu-west-1 \\
        --agent-name basic-agent \\
        --eval-cases-dir agents/basic-agent/eval \\
        --interactive-auth --username alice@example.com
"""

import argparse
import getpass
import json
import sys
import time
import urllib.parse
import uuid
from datetime import timedelta
from pathlib import Path

import boto3
import requests
from bedrock_agentcore.evaluation import EvaluationClient, ReferenceInputs

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DEFAULT_EVALUATORS = [
    "Builtin.Helpfulness",
    "Builtin.GoalSuccessRate",
]

DEFAULT_EVAL_CASES = [
    {
        "name": "Greeting and capabilities",
        "prompt": "Hello, how are you? What can you help me with?",
        "assertions": [
            "Agent responded politely",
            "Agent described its capabilities or available tools",
        ],
        "trajectory": [],
        "expected_response": None,
    },
]

PASS_THRESHOLD = 0.6
CW_INGESTION_DELAY = 90
EVAL_RETRY_DELAY = 60


# ---------------------------------------------------------------------------
# Eval case loading
# ---------------------------------------------------------------------------
def _parse_cases_file(path: Path):
    """Parse a YAML or JSON eval-cases file. Accepts a bare list or {cases: [...]}."""
    text = path.read_text()
    if path.suffix.lower() in (".yaml", ".yml"):
        import yaml

        data = yaml.safe_load(text)
    else:
        data = json.loads(text)

    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        return data.get("cases", [])
    return []


def load_eval_cases(cases_dir=None, cases_file=None):
    """Load eval cases from a directory (preferred) or single file.

    Directory mode globs *.yaml, *.yml, *.json at the top level and collects
    every case. File mode loads just that file.
    """
    if cases_dir:
        root = Path(cases_dir)
        if not root.is_dir():
            print(f"  WARN: --eval-cases-dir {cases_dir} is not a directory")
            return DEFAULT_EVAL_CASES

        files = sorted(
            [
                p
                for p in root.iterdir()
                if p.suffix.lower() in (".yaml", ".yml", ".json")
            ]
        )
        all_cases = []
        for f in files:
            try:
                cases = _parse_cases_file(f)
                if cases:
                    print(f"  Loaded {len(cases)} case(s) from {f.name}")
                    all_cases.extend(cases)
            except Exception as e:
                print(f"  WARN: Failed to parse {f}: {e}")
        return all_cases or DEFAULT_EVAL_CASES

    if cases_file:
        try:
            cases = _parse_cases_file(Path(cases_file))
            if cases:
                print(f"  Loaded {len(cases)} case(s) from {cases_file}")
                return cases
        except Exception as e:
            print(f"  WARN: Failed to load {cases_file}: {e}")

    return DEFAULT_EVAL_CASES


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
def get_auth_token_pipeline(region, stack="fastagent-enterprise"):
    """Headless auth for CI: creds in AWS Secrets Manager, client-id in AWS Systems Manager Parameter Store."""
    ssm = boto3.client("ssm", region_name=region)
    client_id = ssm.get_parameter(Name=f"/{stack}/cognito-user-pool-client-id")[
        "Parameter"
    ]["Value"]

    secret = boto3.client("secretsmanager", region_name=region)
    creds = json.loads(
        secret.get_secret_value(SecretId=f"/{stack}/pipeline_eval_credentials")[
            "SecretString"
        ]
    )

    cognito = boto3.client("cognito-idp", region_name=region)
    resp = cognito.initiate_auth(
        ClientId=client_id,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={
            "USERNAME": creds["username"],
            "PASSWORD": creds["password"],
        },
    )
    return resp["AuthenticationResult"]["AccessToken"]


def get_auth_token_interactive(region, username, password=None):
    """Interactive auth for local dev. Resolves Cognito client from CFN outputs."""
    if not password:
        password = getpass.getpass(f"Password for {username}: ")

    # Resolve pool/client from agentcore stack outputs.
    # Try the shared helper first; fall back to the single-account CFN export name.
    try:
        sys.path.insert(
            0, str(Path(__file__).resolve().parents[1] / "agentcore" / "scripts")
        )
        from utils import authenticate_cognito, get_stack_config

        config = get_stack_config()
        outputs = config["outputs"]
        token, _, _ = authenticate_cognito(
            outputs["CognitoUserPoolId"], outputs["CognitoClientId"], username, password
        )
        return token
    except Exception as e:
        print(f"  WARN: Falling back to direct Cognito auth ({e})")
        cfn = boto3.client("cloudformation", region_name=region)
        outputs = {
            o["OutputKey"]: o["OutputValue"]
            for o in cfn.describe_stacks(StackName="agentic-ai-platform-single")[
                "Stacks"
            ][0]["Outputs"]
        }
        cognito = boto3.client("cognito-idp", region_name=region)
        resp = cognito.initiate_auth(
            ClientId=outputs["CognitoClientId"],
            AuthFlow="USER_PASSWORD_AUTH",
            AuthParameters={"USERNAME": username, "PASSWORD": password},
        )
        return resp["AuthenticationResult"]["AccessToken"]


# ---------------------------------------------------------------------------
# Runtime readiness + invocation
# ---------------------------------------------------------------------------
def wait_for_runtime_ready(runtime_arn, region, timeout=300, poll_interval=15):
    """Wait for the agent runtime to reach READY status."""
    # Amazon Bedrock AgentCore control plane client
    client = boto3.client("bedrock-agentcore-control", region_name=region)
    runtime_id = runtime_arn.split("/")[-1] if "/" in runtime_arn else runtime_arn
    start = time.time()
    while time.time() - start < timeout:
        try:
            resp = client.get_agent_runtime(agentRuntimeId=runtime_id)
            status = resp.get("status", "UNKNOWN")
            if status == "READY":
                print("  Runtime is READY")
                return True
            print(f"  Runtime status: {status}, waiting {poll_interval}s...")
            time.sleep(poll_interval)
        except Exception as e:
            print(f"  Error checking runtime status: {e}")
            time.sleep(poll_interval)
    print(f"  Timeout after {timeout}s waiting for runtime")
    return False


def invoke_agent(runtime_arn, token, prompt, region, session_id):
    """Invoke the agent runtime via HTTPS with Amazon Cognito Bearer token."""
    # Amazon Bedrock AgentCore runtime endpoint
    endpoint = f"https://bedrock-agentcore.{region}.amazonaws.com"
    escaped = urllib.parse.quote(runtime_arn, safe="")
    url = f"{endpoint}/runtimes/{escaped}/invocations?qualifier=DEFAULT"
    payload = json.dumps({"prompt": prompt, "runtimeSessionId": session_id}).encode()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id": session_id,
    }
    if not url.startswith("https://"):
        raise ValueError(f"Refusing to call non-https endpoint: {url}")
    start = time.time()
    try:
        resp = requests.post(url, data=payload, headers=headers, timeout=300)
        resp.raise_for_status()
        body = resp.text
        latency_ms = round((time.time() - start) * 1000)
        text = ""
        for line in body.split("\n"):
            line = line.strip()
            if not line.startswith("data: "):
                continue
            try:
                evt = json.loads(line[6:])
                if isinstance(evt.get("data"), str):
                    text += evt["data"]
                elif evt.get("message", {}).get("content"):
                    for block in evt["message"]["content"]:
                        if "text" in block:
                            text += block["text"]
            except (json.JSONDecodeError, KeyError):
                continue
        return {"ok": True, "text": text, "latency_ms": latency_ms}
    except Exception as e:
        return {
            "ok": False,
            "text": "",
            "error": str(e),
            "latency_ms": round((time.time() - start) * 1000),
        }


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------
def run_evaluation(eval_client, agent_id, session_id, scenario, evaluator_ids):
    """Run evaluation for a single scenario with retry on incomplete spans."""
    ref_kwargs = {}
    if scenario.get("assertions"):
        ref_kwargs["assertions"] = scenario["assertions"]
    if scenario.get("trajectory"):
        ref_kwargs["expected_trajectory"] = scenario["trajectory"]
    if scenario.get("expected_response"):
        ref_kwargs["expected_response"] = scenario["expected_response"]

    reference_inputs = ReferenceInputs(**ref_kwargs) if ref_kwargs else None

    eval_kwargs = {
        "evaluator_ids": evaluator_ids,
        "session_id": session_id,
        "agent_id": agent_id,
        "look_back_time": timedelta(minutes=15),
    }
    if reference_inputs:
        eval_kwargs["reference_inputs"] = reference_inputs

    for attempt in range(2):
        try:
            results = eval_client.run(**eval_kwargs)
        except Exception as e:
            if attempt == 0:
                print(f"      Evaluation error: {e}")
                print(f"      Retrying in {EVAL_RETRY_DELAY}s...")
                time.sleep(EVAL_RETRY_DELAY)
                continue
            print(f"      Evaluation failed after retry: {e}")
            return []

        has_error = any(r.get("errorCode") for r in results)
        if has_error and attempt == 0:
            print(f"      Incomplete spans, retrying in {EVAL_RETRY_DELAY}s...")
            time.sleep(EVAL_RETRY_DELAY)
            continue
        break

    return results


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def publish_eval_metrics(
    agent_name, overall_score, case_results, evaluator_ids, region
):
    """Publish evaluation scores as CloudWatch custom metrics."""
    cw = boto3.client("cloudwatch", region_name=region)
    namespace = "AgentPlatform/Evaluations"
    timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    metric_data = [
        {
            "MetricName": "OverallScore",
            "Dimensions": [{"Name": "AgentName", "Value": agent_name}],
            "Value": overall_score,
            "Unit": "None",
            "Timestamp": timestamp,
        },
    ]

    evaluator_scores = {}
    for case in case_results:
        if case.get("status") != "evaluated":
            continue
        for evaluator, data in case.get("scores", {}).items():
            if isinstance(data, dict) and "score" in data:
                evaluator_scores.setdefault(evaluator, []).append(data["score"])

    for evaluator, scores in evaluator_scores.items():
        avg = sum(scores) / len(scores)
        metric_data.append(
            {
                "MetricName": evaluator.replace("Builtin.", ""),
                "Dimensions": [{"Name": "AgentName", "Value": agent_name}],
                "Value": avg,
                "Unit": "None",
                "Timestamp": timestamp,
            }
        )

    latencies = [c["latency_ms"] for c in case_results if c.get("latency_ms")]
    if latencies:
        metric_data.append(
            {
                "MetricName": "InvocationLatency",
                "Dimensions": [{"Name": "AgentName", "Value": agent_name}],
                "Value": sum(latencies) / len(latencies),
                "Unit": "Milliseconds",
                "Timestamp": timestamp,
            }
        )

    try:
        cw.put_metric_data(Namespace=namespace, MetricData=metric_data)
        print(f"  Published {len(metric_data)} metrics to {namespace}")
    except Exception as e:
        print(f"  WARN: Failed to publish metrics: {e}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Agent on-demand evaluation using AgentCore EvaluationClient"
    )
    parser.add_argument("--runtime-arn", required=True)
    parser.add_argument("--region", default="eu-west-1")
    parser.add_argument("--agent-name", default="agent")
    parser.add_argument(
        "--eval-cases-dir",
        default=None,
        help="Directory of *.yaml/*.json eval cases (preferred). Cases are merged.",
    )
    parser.add_argument(
        "--eval-cases", default=None, help="Path to a single eval_cases.yaml/json"
    )
    parser.add_argument("--stack-name", default="fastagent-enterprise")
    parser.add_argument("--threshold", type=float, default=PASS_THRESHOLD)
    parser.add_argument(
        "--evaluators",
        nargs="*",
        default=None,
        help="Evaluator IDs (default: Builtin.Helpfulness, Builtin.GoalSuccessRate)",
    )
    parser.add_argument(
        "--span-wait",
        type=int,
        default=CW_INGESTION_DELAY,
        help="Seconds to wait for span ingestion (default: 90)",
    )
    parser.add_argument(
        "--results-file",
        default=None,
        help="Output path (default: eval-results/<agent-name>.json)",
    )
    # Local-dev auth
    parser.add_argument(
        "--interactive-auth",
        action="store_true",
        help="Prompt for Cognito credentials instead of pulling from Secrets Manager",
    )
    parser.add_argument(
        "--username", default=None, help="Cognito username (with --interactive-auth)"
    )
    parser.add_argument(
        "--password",
        default=None,
        help="Cognito password (with --interactive-auth; prompts if omitted)",
    )
    args = parser.parse_args()

    evaluator_ids = args.evaluators or DEFAULT_EVALUATORS
    agent_id = args.runtime_arn.rsplit("/", 1)[-1]

    print("=" * 60)
    print("  AgentCore On-Demand Evaluation")
    print("=" * 60)
    print(f"  Agent:      {args.agent_name}")
    print(f"  Runtime:    {args.runtime_arn}")
    print(f"  Agent ID:   {agent_id}")
    print(f"  Evaluators: {', '.join(evaluator_ids)}")
    print(f"  Threshold:  {args.threshold}")
    print()

    # Load cases
    cases = load_eval_cases(cases_dir=args.eval_cases_dir, cases_file=args.eval_cases)
    print(f"  Cases: {len(cases)}")
    print()

    # Auth
    print("Authenticating...")
    if args.interactive_auth:
        if not args.username:
            parser.error("--interactive-auth requires --username")
        token = get_auth_token_interactive(args.region, args.username, args.password)
    else:
        token = get_auth_token_pipeline(args.region, args.stack_name)
    print("Authenticated.\n")

    # Runtime readiness
    print("Step 0: Checking runtime readiness...")
    if not wait_for_runtime_ready(args.runtime_arn, args.region):
        print("ERROR: Runtime did not become ready. Cannot evaluate.")
        sys.exit(1)

    # Invoke each case serially. The 90s span-ingestion wait dominates
    # total runtime, so parallelism here rarely pays off and adds log noise.
    print(f"\nStep 1: Invoking agent for {len(cases)} scenario(s)...")
    sessions = []
    for i, case in enumerate(cases):
        session_id = f"eval-{uuid.uuid4()}"
        prompt = case.get("prompt", case.get("input", ""))
        name = case.get("name", f"case-{i + 1}")
        print(f"  [{i + 1}/{len(cases)}] {name}: {prompt[:60]}...", end=" ", flush=True)

        response = invoke_agent(
            args.runtime_arn, token, prompt, args.region, session_id
        )
        if response["ok"]:
            print(f"OK ({response['latency_ms']}ms)")
        else:
            print(f"FAIL ({response.get('error', 'unknown')[:80]})")
        sessions.append((case, session_id, response))

    successful = sum(1 for _, _, r in sessions if r["ok"])
    print(f"\n  Invocations: {successful}/{len(cases)} successful")
    if successful == 0:
        print("\nERROR: All invocations failed. Cannot evaluate.")
        sys.exit(1)

    # Wait for span ingestion
    print(f"\nStep 2: Waiting {args.span_wait}s for CloudWatch span ingestion...")
    time.sleep(args.span_wait)

    # Evaluate
    print("\nStep 3: Running AgentCore evaluations...")
    eval_client = EvaluationClient(region_name=args.region)
    all_case_results = []
    all_scores = []

    for i, (case, session_id, response) in enumerate(sessions):
        name = case.get("name", f"case-{i + 1}")
        print(f"\n  [{name}] session={session_id}")

        if not response["ok"]:
            print("    SKIPPED (invocation failed)")
            all_case_results.append(
                {
                    "name": name,
                    "session_id": session_id,
                    "status": "invocation_failed",
                    "scores": {},
                    "error": response.get("error"),
                }
            )
            continue

        results = run_evaluation(eval_client, agent_id, session_id, case, evaluator_ids)

        case_scores = {}
        for r in results:
            evaluator = r.get("evaluatorId", r.get("evaluatorName", "unknown"))
            if r.get("errorCode"):
                print(f"    {evaluator}: ERROR — {r.get('errorMessage', '')[:100]}")
                case_scores[evaluator] = {"error": r.get("errorMessage", "")}
            else:
                score = r.get("value", 0.0)
                label = r.get("label", "")
                print(f"    {evaluator}: {score:.3f} ({label})")
                case_scores[evaluator] = {"score": score, "label": label}
                all_scores.append(score)

        all_case_results.append(
            {
                "name": name,
                "session_id": session_id,
                "status": "evaluated",
                "scores": case_scores,
                "response_preview": response["text"][:200],
                "latency_ms": response["latency_ms"],
            }
        )

    # Summary + gate
    overall_score = sum(all_scores) / len(all_scores) if all_scores else 0.0
    overall_pass = overall_score >= args.threshold and len(all_scores) > 0

    print("\nStep 4: Publishing metrics to CloudWatch...")
    publish_eval_metrics(
        args.agent_name, overall_score, all_case_results, evaluator_ids, args.region
    )

    summary = {
        "agent_name": args.agent_name,
        "runtime_arn": args.runtime_arn,
        "agent_id": agent_id,
        "overall": "PASS" if overall_pass else "FAIL",
        "overall_score": round(overall_score, 3),
        "threshold": args.threshold,
        "evaluators": evaluator_ids,
        "total_scores": len(all_scores),
        "cases": all_case_results,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    results_path = Path(args.results_file or f"eval-results/{args.agent_name}.json")
    results_path.parent.mkdir(parents=True, exist_ok=True)
    with open(results_path, "w") as f:
        json.dump(summary, f, indent=2)

    print(f"\n{'=' * 60}")
    print(f"  Agent:    {args.agent_name}")
    print(f"  Overall:  {'PASS' if overall_pass else 'FAIL'}")
    print(f"  Score:    {overall_score:.3f} (threshold: {args.threshold})")
    print(f"  Evals:    {len(all_scores)} scores across {len(cases)} cases")
    print(f"  Results:  {results_path}")
    print(f"{'=' * 60}")

    sys.exit(0 if overall_pass else 1)


if __name__ == "__main__":
    main()
