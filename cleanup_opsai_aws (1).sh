#!/usr/bin/env bash
set -Eeuo pipefail

export AWS_PAGER=""

PROJECT_DIR="${HOME}/opsai-assistant-aws"
ENV_FILE="${PROJECT_DIR}/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$AWS_REGION}"
export AWS_REGION AWS_DEFAULT_REGION

AGENT_NAME="opsai-assistant-agent"
ALIAS_NAME="opsai-mvp"
KB_NAME="opsai-assistant-kb"
DATA_SOURCE_NAME="opsai-runbooks-s3"
LAMBDA_FUNCTION_NAME="${LAMBDA_FUNCTION_NAME:-opsai-assistant-api}"
LAMBDA_ROLE_NAME="OpsAILambdaExecutionRole"
API_NAME="opsai-assistant-http-api"
AMPLIFY_APP_NAME="opsai-assistant-ui"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
CURRENT_ARN="$(aws sts get-caller-identity --query Arn --output text)"
KNOWLEDGE_BUCKET="${OPSAI_BUCKET:-opsai-assistant-kb-${ACCOUNT_ID}-${AWS_REGION}}"

valid_value() {
  [[ -n "${1:-}" && "$1" != "None" && "$1" != "null" ]]
}

echo "============================================================"
echo " OpsAI Assistant - COMPLETE AWS CLEANUP"
echo "============================================================"
echo "AWS account : $ACCOUNT_ID"
echo "AWS identity: $CURRENT_ARN"
echo "AWS region  : $AWS_REGION"
echo
echo "This cleanup permanently removes:"
echo "  - Amplify app:       $AMPLIFY_APP_NAME"
echo "  - API Gateway API:   $API_NAME"
echo "  - Lambda function:   $LAMBDA_FUNCTION_NAME"
echo "  - CloudWatch logs:   /aws/lambda/$LAMBDA_FUNCTION_NAME"
echo "  - Bedrock agent:     $AGENT_NAME"
echo "  - Bedrock KB:        $KB_NAME"
echo "  - S3 vector index and vector bucket used by the KB"
echo "  - S3 knowledge bucket: $KNOWLEDGE_BUCKET"
echo "  - OpsAI Lambda, Bedrock Agent, and Bedrock KB IAM roles"
echo
echo "This action cannot be undone."
echo

read -r -p "Type DELETE-OPSAI-${ACCOUNT_ID} to continue: " CONFIRM
if [[ "$CONFIRM" != "DELETE-OPSAI-${ACCOUNT_ID}" ]]; then
  echo "Confirmation did not match. Cleanup cancelled."
  exit 1
fi

LOG_FILE="${HOME}/opsai-cleanup-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo
echo "Cleanup started at: $(date)"
echo "Log file: $LOG_FILE"

# -------------------------------------------------------------------
# Discover resources before deleting them.
# -------------------------------------------------------------------
AMPLIFY_APP_ID="$(aws amplify list-apps \
  --region "$AWS_REGION" \
  --query "apps[?name=='${AMPLIFY_APP_NAME}'].appId | [0]" \
  --output text 2>/dev/null || true)"

API_ID="$(aws apigatewayv2 get-apis \
  --region "$AWS_REGION" \
  --query "Items[?Name=='${API_NAME}'].ApiId | [0]" \
  --output text 2>/dev/null || true)"

AGENT_ID="$(aws bedrock-agent list-agents \
  --region "$AWS_REGION" \
  --query "agentSummaries[?agentName=='${AGENT_NAME}'].agentId | [0]" \
  --output text 2>/dev/null || true)"

KB_ID="$(aws bedrock-agent list-knowledge-bases \
  --region "$AWS_REGION" \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" \
  --output text 2>/dev/null || true)"

AGENT_ROLE_ARN=""
KB_ROLE_ARN=""
VECTOR_BUCKET_ARN=""
VECTOR_INDEX_ARN=""

if valid_value "$AGENT_ID"; then
  AGENT_ROLE_ARN="$(aws bedrock-agent get-agent \
    --agent-id "$AGENT_ID" \
    --region "$AWS_REGION" \
    --query 'agent.agentResourceRoleArn' \
    --output text 2>/dev/null || true)"
fi

if valid_value "$KB_ID"; then
  KB_ROLE_ARN="$(aws bedrock-agent get-knowledge-base \
    --knowledge-base-id "$KB_ID" \
    --region "$AWS_REGION" \
    --query 'knowledgeBase.roleArn' \
    --output text 2>/dev/null || true)"

  VECTOR_BUCKET_ARN="$(aws bedrock-agent get-knowledge-base \
    --knowledge-base-id "$KB_ID" \
    --region "$AWS_REGION" \
    --query 'knowledgeBase.storageConfiguration.s3VectorsConfiguration.vectorBucketArn' \
    --output text 2>/dev/null || true)"

  VECTOR_INDEX_ARN="$(aws bedrock-agent get-knowledge-base \
    --knowledge-base-id "$KB_ID" \
    --region "$AWS_REGION" \
    --query 'knowledgeBase.storageConfiguration.s3VectorsConfiguration.indexArn' \
    --output text 2>/dev/null || true)"
fi

echo
echo "Discovered resources:"
echo "  Amplify App ID : ${AMPLIFY_APP_ID:-Not found}"
echo "  API ID         : ${API_ID:-Not found}"
echo "  Agent ID       : ${AGENT_ID:-Not found}"
echo "  KB ID          : ${KB_ID:-Not found}"
echo "  Vector bucket  : ${VECTOR_BUCKET_ARN:-Not found}"
echo "  Vector index   : ${VECTOR_INDEX_ARN:-Not found}"

# -------------------------------------------------------------------
# 1. Delete Amplify hosting app.
# -------------------------------------------------------------------
echo
echo "[1/9] Deleting Amplify app..."
if valid_value "$AMPLIFY_APP_ID"; then
  aws amplify delete-app \
    --app-id "$AMPLIFY_APP_ID" \
    --region "$AWS_REGION" >/dev/null
  echo "Deleted Amplify app: $AMPLIFY_APP_ID"
else
  echo "Amplify app not found. Skipped."
fi

# -------------------------------------------------------------------
# 2. Delete API Gateway HTTP API.
# -------------------------------------------------------------------
echo
echo "[2/9] Deleting API Gateway API..."
if valid_value "$API_ID"; then
  aws apigatewayv2 delete-api \
    --api-id "$API_ID" \
    --region "$AWS_REGION"
  echo "Deleted API Gateway API: $API_ID"
else
  echo "API Gateway API not found. Skipped."
fi

# -------------------------------------------------------------------
# 3. Delete Lambda function and CloudWatch log group.
# -------------------------------------------------------------------
echo
echo "[3/9] Deleting Lambda function and logs..."
if aws lambda get-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda delete-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --region "$AWS_REGION"
  echo "Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
else
  echo "Lambda function not found. Skipped."
fi

LOG_GROUP="/aws/lambda/${LAMBDA_FUNCTION_NAME}"
if aws logs describe-log-groups \
  --log-group-name-prefix "$LOG_GROUP" \
  --region "$AWS_REGION" \
  --query "logGroups[?logGroupName=='${LOG_GROUP}'].logGroupName | [0]" \
  --output text 2>/dev/null | grep -qx "$LOG_GROUP"; then
  aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$AWS_REGION"
  echo "Deleted CloudWatch log group: $LOG_GROUP"
else
  echo "CloudWatch log group not found. Skipped."
fi

# -------------------------------------------------------------------
# 4. Delete Bedrock agent aliases and agent.
# -------------------------------------------------------------------
echo
echo "[4/9] Deleting Bedrock agent..."
if valid_value "$AGENT_ID"; then
  ALIAS_IDS="$(aws bedrock-agent list-agent-aliases \
    --agent-id "$AGENT_ID" \
    --region "$AWS_REGION" \
    --query "agentAliasSummaries[?agentAliasId!='TSTALIASID'].agentAliasId" \
    --output text 2>/dev/null || true)"

  if valid_value "$ALIAS_IDS"; then
    for ALIAS_ID in $ALIAS_IDS; do
      aws bedrock-agent delete-agent-alias \
        --agent-id "$AGENT_ID" \
        --agent-alias-id "$ALIAS_ID" \
        --region "$AWS_REGION" >/dev/null || true
      echo "Requested deletion of agent alias: $ALIAS_ID"
    done
  fi

  # Remove the DRAFT association when present.
  if valid_value "$KB_ID"; then
    aws bedrock-agent disassociate-agent-knowledge-base \
      --agent-id "$AGENT_ID" \
      --agent-version DRAFT \
      --knowledge-base-id "$KB_ID" \
      --region "$AWS_REGION" >/dev/null 2>&1 || true
  fi

  aws bedrock-agent delete-agent \
    --agent-id "$AGENT_ID" \
    --skip-resource-in-use-check \
    --region "$AWS_REGION" >/dev/null

  for _ in {1..30}; do
    if ! aws bedrock-agent get-agent \
      --agent-id "$AGENT_ID" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  echo "Deleted Bedrock agent: $AGENT_ID"
else
  echo "Bedrock agent not found. Skipped."
fi

# -------------------------------------------------------------------
# 5. Delete Bedrock data source and knowledge base.
# -------------------------------------------------------------------
echo
echo "[5/9] Deleting Bedrock Knowledge Base..."
if valid_value "$KB_ID"; then
  DATA_SOURCE_IDS="$(aws bedrock-agent list-data-sources \
    --knowledge-base-id "$KB_ID" \
    --region "$AWS_REGION" \
    --query 'dataSourceSummaries[].dataSourceId' \
    --output text 2>/dev/null || true)"

  if valid_value "$DATA_SOURCE_IDS"; then
    for DATA_SOURCE_ID in $DATA_SOURCE_IDS; do
      aws bedrock-agent delete-data-source \
        --knowledge-base-id "$KB_ID" \
        --data-source-id "$DATA_SOURCE_ID" \
        --region "$AWS_REGION" >/dev/null || true
      echo "Requested deletion of data source: $DATA_SOURCE_ID"
    done

    for _ in {1..30}; do
      REMAINING_DS="$(aws bedrock-agent list-data-sources \
        --knowledge-base-id "$KB_ID" \
        --region "$AWS_REGION" \
        --query 'length(dataSourceSummaries)' \
        --output text 2>/dev/null || echo 0)"
      [[ "$REMAINING_DS" == "0" ]] && break
      sleep 5
    done
  fi

  aws bedrock-agent delete-knowledge-base \
    --knowledge-base-id "$KB_ID" \
    --region "$AWS_REGION" >/dev/null

  for _ in {1..40}; do
    if ! aws bedrock-agent get-knowledge-base \
      --knowledge-base-id "$KB_ID" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      break
    fi
    sleep 5
  done

  echo "Deleted Bedrock Knowledge Base: $KB_ID"
else
  echo "Bedrock Knowledge Base not found. Skipped."
fi

# -------------------------------------------------------------------
# 6. Delete S3 vector index and vector bucket.
# -------------------------------------------------------------------
echo
echo "[6/9] Deleting S3 vector resources..."
if valid_value "$VECTOR_INDEX_ARN"; then
  aws s3vectors delete-index \
    --index-arn "$VECTOR_INDEX_ARN" \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
  echo "Requested deletion of vector index: $VECTOR_INDEX_ARN"
else
  echo "Vector index ARN not found. Skipped."
fi

if valid_value "$VECTOR_BUCKET_ARN"; then
  for ATTEMPT in {1..20}; do
    if aws s3vectors delete-vector-bucket \
      --vector-bucket-arn "$VECTOR_BUCKET_ARN" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      echo "Deleted vector bucket: $VECTOR_BUCKET_ARN"
      break
    fi

    if [[ "$ATTEMPT" == "20" ]]; then
      echo "WARNING: Vector bucket was not deleted."
      echo "Review it in Amazon S3 > Vector buckets."
    else
      sleep 5
    fi
  done
else
  echo "Vector bucket ARN not found. Skipped."
fi

# -------------------------------------------------------------------
# 7. Empty and delete the versioned S3 knowledge bucket.
# -------------------------------------------------------------------
echo
echo "[7/9] Deleting S3 knowledge bucket and all versions..."
if aws s3api head-bucket --bucket "$KNOWLEDGE_BUCKET" 2>/dev/null; then
  python3 - "$KNOWLEDGE_BUCKET" "$AWS_REGION" <<'PY'
import sys
import boto3
from botocore.exceptions import ClientError

bucket_name = sys.argv[1]
region = sys.argv[2]
s3 = boto3.resource("s3", region_name=region)
bucket = s3.Bucket(bucket_name)

# Deletes object versions and delete markers in batches.
bucket.object_versions.delete()

# Handles any remaining current objects.
bucket.objects.all().delete()

bucket.delete()
print(f"Deleted S3 bucket: {bucket_name}")
PY
else
  echo "S3 knowledge bucket not found or not accessible. Skipped."
fi

# -------------------------------------------------------------------
# 8. Delete IAM roles used only by OpsAI.
# -------------------------------------------------------------------
echo
echo "[8/9] Deleting OpsAI IAM roles..."

delete_role() {
  local role_name="$1"

  if [[ -z "$role_name" ]]; then
    return
  fi

  if ! aws iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    echo "IAM role not found: $role_name"
    return
  fi

  local attached
  attached="$(aws iam list-attached-role-policies \
    --role-name "$role_name" \
    --query 'AttachedPolicies[].PolicyArn' \
    --output text 2>/dev/null || true)"

  if valid_value "$attached"; then
    for policy_arn in $attached; do
      aws iam detach-role-policy \
        --role-name "$role_name" \
        --policy-arn "$policy_arn"
    done
  fi

  local inline
  inline="$(aws iam list-role-policies \
    --role-name "$role_name" \
    --query 'PolicyNames[]' \
    --output text 2>/dev/null || true)"

  if valid_value "$inline"; then
    for policy_name in $inline; do
      aws iam delete-role-policy \
        --role-name "$role_name" \
        --policy-name "$policy_name"
    done
  fi

  aws iam delete-role --role-name "$role_name"
  echo "Deleted IAM role: $role_name"
}

declare -A ROLE_NAMES=()
ROLE_NAMES["$LAMBDA_ROLE_NAME"]=1

if valid_value "$AGENT_ROLE_ARN"; then
  ROLE_NAMES["${AGENT_ROLE_ARN##*/}"]=1
fi

if valid_value "$KB_ROLE_ARN"; then
  ROLE_NAMES["${KB_ROLE_ARN##*/}"]=1
fi

for ROLE_NAME in "${!ROLE_NAMES[@]}"; do
  delete_role "$ROLE_NAME"
done

# -------------------------------------------------------------------
# 9. Final verification.
# -------------------------------------------------------------------
echo
echo "[9/9] Final verification..."

printf "Amplify app count: "
aws amplify list-apps \
  --region "$AWS_REGION" \
  --query "length(apps[?name=='${AMPLIFY_APP_NAME}'])" \
  --output text 2>/dev/null || echo "Unable to check"

printf "API Gateway API count: "
aws apigatewayv2 get-apis \
  --region "$AWS_REGION" \
  --query "length(Items[?Name=='${API_NAME}'])" \
  --output text 2>/dev/null || echo "Unable to check"

printf "Lambda function: "
if aws lambda get-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "STILL EXISTS"
else
  echo "Deleted"
fi

printf "Bedrock agent count: "
aws bedrock-agent list-agents \
  --region "$AWS_REGION" \
  --query "length(agentSummaries[?agentName=='${AGENT_NAME}'])" \
  --output text 2>/dev/null || echo "Unable to check"

printf "Knowledge Base count: "
aws bedrock-agent list-knowledge-bases \
  --region "$AWS_REGION" \
  --query "length(knowledgeBaseSummaries[?name=='${KB_NAME}'])" \
  --output text 2>/dev/null || echo "Unable to check"

printf "S3 knowledge bucket: "
if aws s3api head-bucket --bucket "$KNOWLEDGE_BUCKET" 2>/dev/null; then
  echo "STILL EXISTS"
else
  echo "Deleted"
fi

echo
echo "AWS cleanup completed at: $(date)"
echo "Review the warnings above, if any."
echo "Cleanup log: $LOG_FILE"
echo
echo "Local CloudShell files were NOT deleted automatically."
echo "After saving anything you need, remove them with:"
echo "  rm -rf \"$PROJECT_DIR\""
echo
echo "The IAM user 'opsai-admin' was NOT deleted."
echo "Delete that user only from root or another administrator account,"
echo "and only after confirming it is not needed for any other work."
