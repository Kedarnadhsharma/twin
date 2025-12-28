#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 1. Build Lambda package
cd "$(dirname "$0")/.."        # project root
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 2. Terraform workspace & apply
cd terraform
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Build terraform apply command with required variables
TF_VARS=(
  -var="project_name=$PROJECT_NAME"
  -var="environment=$ENVIRONMENT"
)

# Add OpenAI API key if provided via environment variable
if [ -n "$OPENAI_API_KEY" ]; then
  TF_VARS+=(-var="openai_api_key=$OPENAI_API_KEY")
elif [ -n "$TF_VAR_openai_api_key" ]; then
  # TF_VAR_ prefix is automatically picked up by Terraform
  :
else
  echo "⚠️ Warning: OPENAI_API_KEY not set. Terraform may prompt for it."
fi

# Add GitHub repository if provided
if [ -n "$GITHUB_REPOSITORY" ]; then
  TF_VARS+=(-var="github_repository=$GITHUB_REPOSITORY")
elif [ -n "$TF_VAR_github_repository" ]; then
  :
else
  echo "⚠️ Warning: GITHUB_REPOSITORY not set. Terraform may prompt for it."
fi

# Use prod.tfvars for production environment
if [ "$ENVIRONMENT" = "prod" ] && [ -f "prod.tfvars" ]; then
  TF_VARS+=(-var-file=prod.tfvars)
fi

echo "🎯 Applying Terraform..."
terraform apply "${TF_VARS[@]}" -auto-approve

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
FRONTEND_URL=$(terraform output -raw frontend_website_url)

# 3. Build + deploy frontend (if frontend directory exists)
if [ -d "../frontend" ]; then
  cd ../frontend

  # Create production environment file with API URL
  echo "📝 Setting API URL for production..."
  echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

  npm install
  npm run build
  aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
  cd ..
else
  echo "⚠️ Frontend directory not found, skipping frontend deployment"
fi

# 4. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 Frontend URL   : $FRONTEND_URL"
echo "📡 API Gateway    : $API_URL"
