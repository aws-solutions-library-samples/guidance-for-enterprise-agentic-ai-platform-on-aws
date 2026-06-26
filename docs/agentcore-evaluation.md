<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Agent Evaluation

Evaluate your deployed agent using [Amazon Bedrock AgentCore Evaluations](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/evaluations.html).

## Quick Start

Local dev (interactive Cognito login):

```bash
python3 scripts/pipeline_eval.py \
  --runtime-arn <arn> --region <region> \
  --agent-name strands-single-agent \
  --eval-cases-dir agentcore/patterns/strands-single-agent/evals \
  --interactive-auth --username <USER>
```

CI/CD (headless, Secrets Manager auth):

```bash
python3 scripts/pipeline_eval.py \
  --runtime-arn <arn> --region <region> \
  --agent-name <name> \
  --eval-cases-dir agents/<name>/eval
```

## Scenario Format

Drop `*.json` or `*.yaml` files into the eval directory. Each file holds a list
of cases (or `{cases: [...]}`). Every file in the directory is merged — split
by concern (regression, tool-usage, safety) as you grow.

```json
[
  {
    "name": "Simple word count",
    "prompt": "How many words are in this text: 'The quick brown fox jumps over the lazy dog'",
    "assertions": [
      "Agent used a tool to count words",
      "Agent returned the correct word count of 9"
    ],
    "trajectory": ["gateway_sample-tool-target___text_analysis_tool"]
  }
]
```

Fields:
- `name` — case label used in logs and metrics
- `prompt` — the user input sent to the agent
- `assertions` — ground truth for `Builtin.GoalSuccessRate`
- `trajectory` — expected tool sequence for `Builtin.Trajectory*Match`
- `expected_response` (optional) — ground truth for `Builtin.Correctness`

## Built-in Evaluators

| Evaluator | Level | Ground truth |
|---|---|---|
| `Builtin.Correctness` | TRACE | `expected_response` |
| `Builtin.Helpfulness` | TRACE | — |
| `Builtin.ResponseRelevance` | TRACE | — |
| `Builtin.GoalSuccessRate` | SESSION | `assertions` |
| `Builtin.TrajectoryInOrderMatch` | SESSION | `expected_trajectory` |
| `Builtin.TrajectoryAnyOrderMatch` | SESSION | `expected_trajectory` |
| `Builtin.TrajectoryExactOrderMatch` | SESSION | `expected_trajectory` |

Pick evaluators with `--evaluators Builtin.Helpfulness Builtin.GoalSuccessRate`.
Defaults are `Builtin.Helpfulness` and `Builtin.GoalSuccessRate`.

Full list plus custom LLM-as-a-judge evaluators: see the [AgentCore Evaluations tutorial](https://github.com/awslabs/agentcore-samples/tree/main/01-tutorials/07-AgentCore-evaluations/05-groundtruth-based-evalautions).

## How It Works

1. Authenticates (Cognito interactive or Secrets Manager, depending on mode)
2. Waits for the runtime to reach `READY`
3. Invokes the agent for each scenario (generates OTel traces)
4. Waits 90s for CloudWatch span ingestion (`--span-wait` to override)
5. Calls `EvaluationClient.run()` with ground-truth references per case
6. Retries once after 60s if spans are incomplete
7. Publishes per-evaluator scores + invocation latency to CloudWatch
   (`AgentPlatform/Evaluations` namespace)
8. Writes `eval-results/<agent-name>.json` and exits non-zero if the average
   score falls below `--threshold` (default 0.6)