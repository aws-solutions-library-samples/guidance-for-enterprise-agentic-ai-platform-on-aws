<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Deployment Scripts

This directory contains scripts for deploying the Fullstack AgentCore Solution Template
infrastructure.

## Main Deployment Workflow

### Deploy Infrastructure

```bash
cd infra-cdk
cdk deploy
```

This deploys the CDK stack.

## Individual Scripts

### CodeBuild Deployment

- `deploy-with-codebuild.py` - Deploys the FAST stack using an ephemeral CodeBuild project. No local Node.js, Docker, CDK, or npm required — only Python 3.8+ and AWS CLI.

```bash
python scripts/deploy-with-codebuild.py
```

Creates temporary AWS resources (S3 bucket, IAM role with permission boundary, CodeBuild project), runs the full deployment in the cloud, streams logs to your terminal, and cleans up all temporary resources on exit.

The temporary IAM role is created with `AdministratorAccess` but constrained by a permission boundary that explicitly denies dangerous actions such as `iam:CreateUser`, `iam:CreateAccessKey`, `organizations:*`, and others. This prevents privilege escalation even if the build is compromised.

Your IAM user/role needs these permissions to run the script:

- `s3:CreateBucket`, `s3:DeleteBucket`, `s3:PutObject`, `s3:DeleteObject`
- `iam:CreateRole`, `iam:DeleteRole`, `iam:AttachRolePolicy`, `iam:DetachRolePolicy`
- `iam:CreatePolicy`, `iam:DeletePolicy`
- `codebuild:CreateProject`, `codebuild:StartBuild`, `codebuild:BatchGetBuilds`
- `logs:GetLogEvents`
- `sts:GetCallerIdentity`

---

## Requirements

- AWS CLI configured with appropriate permissions
- Python 3.8+ (standard library only, no pip install needed for deployment)
- CDK stack deployed with the required outputs:
  - `CognitoClientId`
  - `CognitoUserPoolId`

## Key Features

- **Cross-Platform**: Works on Windows, Mac, and Linux
- **No Python Dependencies**: Uses only standard library (no virtual environment needed)
- **Automatic Region Detection**: Extracts region directly from CloudFormation stack ARN

## New User Experience

For brand new installations, simply run:

```bash
cd infra-cdk
cdk deploy
```

## Test Scripts

Test scripts have been moved to the `test-scripts/` directory. See [test-scripts/README.md](../test-scripts/README.md) for testing utilities and verification scripts.