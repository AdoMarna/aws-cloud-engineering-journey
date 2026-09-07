#!/bin/bash

set -euo pipefail

readonly REGION="${AWS_REGION:-eu-west-3}"
readonly PROJECT="proj06"
readonly API_NAME="serverless_lambda_gw"
readonly TABLE_NAME="orders-table"
readonly QUEUE_NAME="orders"
readonly DLQ_NAME="orders-dlq"
readonly EVENT_BUS_NAME="orders-event-bus"
readonly EVENT_RULE_NAME="order-processed-rule"
readonly INGEST_FUNCTION="ingestion_lambda_function"
readonly PROCESSOR_FUNCTION="processor_lambda_function"
readonly NOTIFIER_FUNCTION="notifier_lambda_function"

readonly -a LAMBDA_FUNCTIONS=(
	"$INGEST_FUNCTION"
	"$PROCESSOR_FUNCTION"
	"$NOTIFIER_FUNCTION"
)

readonly -a LAMBDA_ROLES=(
	"proj06-lambda-ingestion-role"
	"proj06-lambda-processor-role"
	"proj06-lambda-notifier-role"
)

readonly -a LOG_GROUPS=(
	"/aws/lambda/${INGEST_FUNCTION}"
	"/aws/lambda/${PROCESSOR_FUNCTION}"
	"/aws/lambda/${NOTIFIER_FUNCTION}"
	"/aws/api_gw/${API_NAME}"
)

export AWS_DEFAULT_REGION="$REGION"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

resource_id() {
	local value="${1:-}"
	if [[ -z "$value" || "$value" == "None" || "$value" == "null" ]]
	then
		return 1
	fi
	return 0
}

# ---------------------------------------------------------------------------
# 1. Event Source Mapping (SQS → processor)
# ---------------------------------------------------------------------------

mapping_uuids=$(aws lambda list-event-source-mappings \
	--function-name "$PROCESSOR_FUNCTION" \
	--query "EventSourceMappings[].UUID" \
	--output text 2>/dev/null || true)

if [[ -n "$mapping_uuids" && "$mapping_uuids" != "None" ]]
then
	for uuid in $mapping_uuids
	do
		log "Deleting event source mapping $uuid"
		aws lambda delete-event-source-mapping --uuid "$uuid" >/dev/null
	done
else
	log "No event source mapping on $PROCESSOR_FUNCTION"
fi

# ---------------------------------------------------------------------------
# 2. EventBridge: targets, rule, custom bus
# ---------------------------------------------------------------------------

target_ids=$(aws events list-targets-by-rule \
	--rule "$EVENT_RULE_NAME" \
	--event-bus-name "$EVENT_BUS_NAME" \
	--query "Targets[].Id" \
	--output text 2>/dev/null || true)

if [[ -n "$target_ids" && "$target_ids" != "None" ]]
then
	log "Removing EventBridge targets from $EVENT_RULE_NAME"
	aws events remove-targets \
		--rule "$EVENT_RULE_NAME" \
		--event-bus-name "$EVENT_BUS_NAME" \
		--ids $target_ids \
		>/dev/null
else
	log "No EventBridge targets to remove"
fi

if aws events describe-rule --name "$EVENT_RULE_NAME" --event-bus-name "$EVENT_BUS_NAME" >/dev/null 2>&1
then
	log "Deleting EventBridge rule $EVENT_RULE_NAME"
	aws events delete-rule --name "$EVENT_RULE_NAME" --event-bus-name "$EVENT_BUS_NAME"
else
	log "EventBridge rule $EVENT_RULE_NAME already gone"
fi

if aws events describe-event-bus --name "$EVENT_BUS_NAME" >/dev/null 2>&1
then
	log "Deleting event bus $EVENT_BUS_NAME"
	aws events delete-event-bus --name "$EVENT_BUS_NAME"
else
	log "Event bus $EVENT_BUS_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 3. Lambda functions
# ---------------------------------------------------------------------------

for fn in "${LAMBDA_FUNCTIONS[@]}"
do
	if aws lambda get-function --function-name "$fn" >/dev/null 2>&1
	then
		log "Deleting Lambda $fn"
		aws lambda delete-function --function-name "$fn"
	else
		log "Lambda $fn already gone"
	fi
done

# ---------------------------------------------------------------------------
# 4. HTTP API Gateway
# ---------------------------------------------------------------------------

api_id=$(aws apigatewayv2 get-apis \
	--query "Items[?Name=='$API_NAME'].ApiId | [0]" \
	--output text 2>/dev/null || true)

if resource_id "$api_id"
then
	log "Deleting HTTP API $API_NAME ($api_id)"
	aws apigatewayv2 delete-api --api-id "$api_id"
else
	log "HTTP API $API_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 5. SQS queues (main first — it references the DLQ)
# ---------------------------------------------------------------------------

delete_queue_if_exists() {
	local name="$1"
	local url
	url=$(aws sqs get-queue-url --queue-name "$name" --query QueueUrl --output text 2>/dev/null || true)

	if resource_id "$url"
	then
		log "Purging then deleting queue $name"
		aws sqs purge-queue --queue-url "$url" >/dev/null 2>&1 || true
		aws sqs delete-queue --queue-url "$url"
	else
		log "Queue $name already gone"
	fi
}

delete_queue_if_exists "$QUEUE_NAME"
delete_queue_if_exists "$DLQ_NAME"

# ---------------------------------------------------------------------------
# 6. DynamoDB table
# ---------------------------------------------------------------------------

if aws dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1
then
	log "Deleting DynamoDB table $TABLE_NAME"
	aws dynamodb delete-table --table-name "$TABLE_NAME" >/dev/null
	aws dynamodb wait table-not-exists --table-name "$TABLE_NAME"
	log "Table $TABLE_NAME deleted"
else
	log "DynamoDB table $TABLE_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 7. CloudWatch log groups
# ---------------------------------------------------------------------------

for group in "${LOG_GROUPS[@]}"
do
	found=$(aws logs describe-log-groups \
		--log-group-name-prefix "$group" \
		--query "logGroups[?logGroupName=='$group'].logGroupName | [0]" \
		--output text 2>/dev/null || true)

	if resource_id "$found"
	then
		log "Deleting log group $group"
		aws logs delete-log-group --log-group-name "$group"
	else
		log "Log group $group already gone"
	fi
done

# ---------------------------------------------------------------------------
# 8. IAM roles (detach managed policies, delete inline, then the role)
# ---------------------------------------------------------------------------

for role in "${LAMBDA_ROLES[@]}"
do
	if ! aws iam get-role --role-name "$role" >/dev/null 2>&1
	then
		log "Role $role already gone"
		continue
	fi

	attached=$(aws iam list-attached-role-policies \
		--role-name "$role" \
		--query "AttachedPolicies[].PolicyArn" \
		--output text 2>/dev/null || true)

	if [[ -n "$attached" && "$attached" != "None" ]]
	then
		for policy_arn in $attached
		do
			log "Detaching $policy_arn from $role"
			aws iam detach-role-policy --role-name "$role" --policy-arn "$policy_arn"
		done
	fi

	inline=$(aws iam list-role-policies \
		--role-name "$role" \
		--query "PolicyNames[]" \
		--output text 2>/dev/null || true)

	if [[ -n "$inline" && "$inline" != "None" ]]
	then
		for policy_name in $inline
		do
			log "Deleting inline policy $policy_name from $role"
			aws iam delete-role-policy --role-name "$role" --policy-name "$policy_name"
		done
	fi

	log "Deleting role $role"
	aws iam delete-role --role-name "$role"
done

log "Cleanup complete for project $PROJECT (state bucket left intact)"
