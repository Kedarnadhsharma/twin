# Terraform Bootstrap

This folder contains **one-time setup** resources that must be run **locally** before using GitHub Actions CI/CD.

## What This Creates

| Resource | Purpose |
|----------|---------|
| S3 Bucket | Stores Terraform state remotely |
| DynamoDB Table | Provides state locking |
| GitHub OIDC Provider | Enables GitHub Actions authentication |
| IAM Role | Permissions for GitHub Actions deployments |

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform 1.0+

## Usage

### First-Time Setup

```bash
cd terraform/bootstrap

# Initialize Terraform
terraform init

# Apply the bootstrap configuration
terraform apply -var="github_repository=YourUsername/twin"
```

### Add GitHub Secrets

After running the bootstrap, add these secrets to your GitHub repository:

1. Go to: `https://github.com/YourUsername/twin/settings/secrets/actions`
2. Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_ARN` | (from terraform output) |
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `DEFAULT_AWS_REGION` | `us-east-1` (or your region) |
| `OPENAI_API_KEY` | Your OpenAI API key |

### Import Existing Resources

If the resources already exist, import them:

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Import S3 bucket
terraform import -var="github_repository=YourUsername/twin" \
  aws_s3_bucket.terraform_state twin-terraform-state-${AWS_ACCOUNT_ID}

# Import DynamoDB table
terraform import -var="github_repository=YourUsername/twin" \
  aws_dynamodb_table.terraform_locks twin-terraform-locks

# Import OIDC provider
terraform import -var="github_repository=YourUsername/twin" \
  aws_iam_openid_connect_provider.github \
  arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com

# Import IAM role
terraform import -var="github_repository=YourUsername/twin" \
  aws_iam_role.github_actions github-actions-twin-deploy
```

## Note

These resources are **NOT** managed by the CI/CD pipeline. They are prerequisites for CI/CD to work.

