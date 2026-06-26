#!/usr/bin/env python3

# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Test AgentCore Gateway directly without frontend.

Usage:
    uv run scripts/test-gateway.py
"""

import json
import os
import sys
from pathlib import Path

import boto3
import requests

# Add scripts directory to path for reliable imports
scripts_dir = Path(__file__).parent.parent / "scripts"
if str(scripts_dir) not in sys.path:
    sys.path.insert(0, str(scripts_dir))

from utils import get_ssm_params, get_stack_config, print_msg, print_section


def get_machine_client_secret(user_pool_id: str, client_id: str) -> str:
    """
    Fetch the Cognito machine client's secret directly from the user pool.

    The secret is not copied into Secrets Manager — it lives only in Cognito
    and is read via DescribeUserPoolClient by anything that needs it. The
    caller must have cognito-idp:DescribeUserPoolClient on the pool.
    """
    region = os.environ.get(
        "AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
    )
    cognito = boto3.client("cognito-idp", region_name=region)
    resp = cognito.describe_user_pool_client(
        UserPoolId=user_pool_id,
        ClientId=client_id,
    )
    secret = resp["UserPoolClient"].get("ClientSecret")
    if not secret:
        raise RuntimeError(
            f"Cognito client {client_id} has no ClientSecret. "
            "Confirm the machine client was created with GenerateSecret=true."
        )
    return secret


def fetch_access_token(client_id: str, client_secret: str, token_url: str) -> str:
    """Fetch access token using client credentials flow."""
    response = requests.post(
        token_url,
        data=f"grant_type=client_credentials&client_id={client_id}&client_secret={client_secret}",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        timeout=30,
    )

    if response.status_code != 200:
        print_msg(
            f"Token request failed: {response.status_code} - {response.text}", "error"
        )
        sys.exit(1)

    return response.json()["access_token"]


def list_tools(gateway_url: str, access_token: str) -> dict:
    """List available tools via gateway."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
    }

    payload = {"jsonrpc": "2.0", "id": "list-tools-request", "method": "tools/list"}

    response = requests.post(gateway_url, headers=headers, json=payload, timeout=30)

    if response.status_code != 200:
        print_msg(
            f"Gateway request failed: {response.status_code} - {response.text}", "error"
        )
        sys.exit(1)

    return response.json()


def call_tool(
    gateway_url: str, access_token: str, tool_name: str, arguments: dict
) -> dict:
    """Call a specific tool via gateway."""
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {access_token}",
    }

    payload = {
        "jsonrpc": "2.0",
        "id": "call-tool-request",
        "method": "tools/call",
        "params": {"name": tool_name, "arguments": arguments},
    }

    response = requests.post(gateway_url, headers=headers, json=payload, timeout=30)

    if response.status_code != 200:
        print_msg(
            f"Gateway request failed: {response.status_code} - {response.text}", "error"
        )
        sys.exit(1)

    return response.json()


def main():
    """Main entry point."""
    print_section("AgentCore Gateway Direct Test")

    # Get stack configuration
    stack_cfg = get_stack_config()
    print(f"Stack: {stack_cfg['stack_name']}\n")

    # Fetch SSM parameters
    print("Fetching configuration...")
    cognito_params = get_ssm_params(
        stack_cfg["stack_name"], "cognito-user-pool-id", "cognito-user-pool-client-id"
    )

    # Check if gateway parameters exist
    gateway_params = get_ssm_params(
        stack_cfg["stack_name"], "gateway_url", "machine_client_id", "cognito_provider"
    )

    # Read the machine client secret directly from Cognito (not Secrets Manager)
    client_secret = get_machine_client_secret(
        cognito_params["cognito-user-pool-id"],
        gateway_params["machine_client_id"],
    )

    print_msg("Configuration fetched")

    # Extract gateway configuration
    gateway_url = gateway_params["gateway_url"]
    client_id = gateway_params["machine_client_id"]
    cognito_domain = gateway_params["cognito_provider"]
    token_url = f"https://{cognito_domain}/oauth2/token"

    print(f"Gateway URL: {gateway_url}")
    print(f"Token URL: {token_url}")

    # Get access token
    print_section("Authentication")
    print("Fetching access token...")

    access_token = fetch_access_token(client_id, client_secret, token_url)
    print_msg("Access token obtained")

    # Test gateway
    print_section("Gateway Test")
    print("Calling tools/list...")

    tools = list_tools(gateway_url, access_token)
    print_msg("Gateway call successful")
    print("\nResponse:")
    print(json.dumps(tools, indent=2))

    # Call the text analysis tool using its name from tools/list
    print_section("Tool Call Test")

    tool_list = tools.get("result", {}).get("tools", [])
    if not tool_list:
        print_msg("No tools found in gateway", "error")
        sys.exit(1)

    # Find the text analysis tool by base name (after the ___ target prefix)
    target_tool = "text_analysis_tool"
    tool_name = None
    for t in tool_list:
        if t["name"].endswith(f"___{target_tool}"):
            tool_name = t["name"]
            break

    if not tool_name:
        print_msg(
            f"Tool '{target_tool}' not found. Available: {[t['name'] for t in tool_list]}",
            "error",
        )
        sys.exit(1)

    print(f"Calling tool: {tool_name}...")

    tool_result = call_tool(
        gateway_url,
        access_token,
        tool_name,
        {
            "text": "Hello world! This is a sample text for analysis. Hello again!",
            "N": 3,
        },
    )

    # Validate response
    if "error" in tool_result:
        print_msg(f"Tool returned error: {tool_result['error']}", "error")
        sys.exit(1)

    if "result" not in tool_result or "content" not in tool_result["result"]:
        print_msg(f"Unexpected response format: {json.dumps(tool_result)}", "error")
        sys.exit(1)

    print_msg("Tool call successful")
    print("\nResponse:")
    print(json.dumps(tool_result, indent=2))


if __name__ == "__main__":
    main()
