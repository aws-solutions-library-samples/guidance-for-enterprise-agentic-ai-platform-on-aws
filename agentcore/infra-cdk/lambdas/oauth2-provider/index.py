# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

"""
Custom Resource Lambda for managing OAuth2 Credential Provider lifecycle.

This Lambda is invoked by CloudFormation during stack deployment to manage
an OAuth2 Credential Provider in Bedrock AgentCore Identity. It fetches the
Cognito machine-client credentials directly from the user pool via
`DescribeUserPoolClient`, so no Secrets Manager copy of the client secret
needs to exist in the account.

In enterprise mode the Cognito pool lives in the Security account and this
Lambda runs in a workload account. In that case an `AssumeRoleArn` is passed
in the resource properties and we transparently switch to a cognito-idp
client that uses temporary credentials from that role.

CloudFormation Events:
- Create: Creates OAuth2 provider with credentials read from Cognito
- Update: Updates OAuth2 provider properties (clientId, clientSecret, discoveryUrl)
- Delete: Deletes OAuth2 provider by name
"""

import logging

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock_client = boto3.client("bedrock-agentcore-control")
sts_client = boto3.client("sts")


def _cognito_client(assume_role_arn: str | None):
    """Return a cognito-idp client, optionally using cross-account credentials."""
    if not assume_role_arn:
        return boto3.client("cognito-idp")
    logger.info(f"Assuming {assume_role_arn} for cross-account Cognito describe")
    creds = sts_client.assume_role(
        RoleArn=assume_role_arn,
        RoleSessionName="oauth2-provider-describe-client",
    )["Credentials"]
    return boto3.client(
        "cognito-idp",
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def _describe_client_secret(props: dict) -> str:
    """Fetch the Cognito machine client's secret. Never logged."""
    user_pool_id = props["UserPoolId"]
    client_id = props["ClientId"]
    assume_role_arn = props.get("AssumeRoleArn") or None

    logger.info(f"Describing Cognito client {client_id} in pool {user_pool_id}")
    cognito = _cognito_client(assume_role_arn)
    resp = cognito.describe_user_pool_client(
        UserPoolId=user_pool_id,
        ClientId=client_id,
    )
    secret = resp["UserPoolClient"].get("ClientSecret")
    if not secret:
        raise RuntimeError(
            f"Cognito client {client_id} has no ClientSecret. "
            "Ensure GenerateSecret=true on the UserPoolClient."
        )
    return secret


def handler(event: dict, context: dict) -> dict:
    request_type = event["RequestType"]
    props = event["ResourceProperties"]

    logger.info(f"Request type: {request_type}")
    logger.info(f"Provider name: {props['ProviderName']}")

    try:
        if request_type == "Create":
            return handle_create(props)
        elif request_type == "Delete":
            return handle_delete(event, props)
        elif request_type == "Update":
            return handle_update(event, props)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
    except Exception as e:
        logger.error(f"Error handling {request_type}: {str(e)}", exc_info=True)
        raise


def _get_provider_arn(name: str) -> str:
    """Fetch the ARN of an existing provider via GetOauth2CredentialProvider."""
    resp = bedrock_client.get_oauth2_credential_provider(name=name)
    return resp["credentialProviderArn"]


def handle_create(props: dict) -> dict:
    client_secret = _describe_client_secret(props)
    provider_name = props["ProviderName"]

    config_input = {
        "customOauth2ProviderConfig": {
            "clientId": props["ClientId"],
            "clientSecret": client_secret,
            "oauthDiscovery": {"discoveryUrl": props["DiscoveryUrl"]},
        }
    }

    try:
        logger.info(f"Creating OAuth2 provider: {provider_name}")
        response = bedrock_client.create_oauth2_credential_provider(
            name=provider_name,
            credentialProviderVendor="CustomOauth2",
            oauth2ProviderConfigInput=config_input,
        )
        provider_arn = response["credentialProviderArn"]
    except (
        bedrock_client.exceptions.ValidationException,
        bedrock_client.exceptions.ConflictException,
    ) as e:
        if "already exists" not in str(e):
            raise
        logger.info(f"Provider {provider_name} already exists — updating in place.")
        bedrock_client.update_oauth2_credential_provider(
            name=provider_name,
            credentialProviderVendor="CustomOauth2",
            oauth2ProviderConfigInput=config_input,
        )
        provider_arn = _get_provider_arn(provider_name)

    logger.info(f"Provider ready: {provider_arn}")
    return {
        "PhysicalResourceId": provider_name,
        "Data": {"ProviderArn": provider_arn},
    }


def handle_update(event: dict, props: dict) -> dict:
    provider_name = event["PhysicalResourceId"]
    logger.info(f"Updating OAuth2 provider: {provider_name}")

    client_secret = _describe_client_secret(props)

    bedrock_client.update_oauth2_credential_provider(
        name=provider_name,
        credentialProviderVendor="CustomOauth2",
        oauth2ProviderConfigInput={
            "customOauth2ProviderConfig": {
                "clientId": props["ClientId"],
                "clientSecret": client_secret,
                "oauthDiscovery": {"discoveryUrl": props["DiscoveryUrl"]},
            }
        },
    )

    provider_arn = _get_provider_arn(provider_name)
    logger.info(f"Updated provider: {provider_arn}")

    return {
        "PhysicalResourceId": provider_name,
        "Data": {"ProviderArn": provider_arn},
    }


def handle_delete(event: dict, props: dict) -> dict:
    provider_name = event["PhysicalResourceId"]
    logger.info(f"Deleting OAuth2 provider: {provider_name}")

    try:
        bedrock_client.delete_oauth2_credential_provider(name=provider_name)
        logger.info(f"Deleted provider: {provider_name}")
    except bedrock_client.exceptions.ResourceNotFoundException:
        logger.warning(f"Provider not found (already deleted): {provider_name}")
    except Exception as e:
        logger.error(f"Error deleting provider: {str(e)}")
        raise

    return {"PhysicalResourceId": provider_name}
