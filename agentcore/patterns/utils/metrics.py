# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""Lightweight CloudWatch metrics for agent observability."""

import os
import time

import boto3
from botocore.exceptions import ClientError

_cw_client = None


def _get_client():
    global _cw_client
    if _cw_client is None:
        region = os.environ.get(
            "AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "eu-west-1")
        )
        _cw_client = boto3.client("cloudwatch", region_name=region)
    return _cw_client


def _namespace():
    # Use project name to match the CloudWatch dashboard namespace
    # Falls back to STACK_NAME if PROJECT_NAME isn't set
    return os.environ.get(
        "PROJECT_NAME", os.environ.get("STACK_NAME", "agent-platform")
    )


def emit_invocation_metrics(
    latency_ms: float,
    input_tokens: int = 0,
    output_tokens: int = 0,
    tool_calls: int = 0,
):
    """Emit metrics for a single agent invocation."""
    ns = _namespace()
    metrics = [
        {"MetricName": "AgentInvocations", "Value": 1, "Unit": "Count"},
        {"MetricName": "AgentLatency", "Value": latency_ms, "Unit": "Milliseconds"},
    ]

    if input_tokens > 0:
        metrics.append(
            {"MetricName": "InputTokens", "Value": input_tokens, "Unit": "Count"}
        )

    if output_tokens > 0:
        metrics.append(
            {"MetricName": "OutputTokens", "Value": output_tokens, "Unit": "Count"}
        )

    if tool_calls > 0:
        metrics.append(
            {"MetricName": "ToolCallSuccess", "Value": tool_calls, "Unit": "Count"}
        )

    try:
        _get_client().put_metric_data(Namespace=ns, MetricData=metrics)
    except ClientError as e:
        print(f"[METRICS] Failed to emit metrics: {e}")


class InvocationTimer:
    """Context manager to time and emit metrics for an invocation."""

    def __init__(self):
        self.start_time = None
        self.input_tokens = 0
        self.output_tokens = 0
        self.tool_calls = 0

    def __enter__(self):
        self.start_time = time.time()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        latency_ms = (time.time() - self.start_time) * 1000
        print(
            f"[METRICS] Emitting: latency={latency_ms:.0f}ms, "
            f"input_tokens={self.input_tokens}, output_tokens={self.output_tokens}, "
            f"tool_calls={self.tool_calls}"
        )
        emit_invocation_metrics(
            latency_ms=latency_ms,
            input_tokens=self.input_tokens,
            output_tokens=self.output_tokens,
            tool_calls=self.tool_calls,
        )
        return False  # Don't suppress exceptions
