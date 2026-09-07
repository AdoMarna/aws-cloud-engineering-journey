#!/bin/bash

set -euo pipefail

readonly REGION="${AWS_REGION:-eu-west-3}"
readonly PROJECT="proj06"
readonly API_NAME="serverless_lambda_gw"
readonly TABLE_NAME="orders-table"
readonly QUEUE_NAME="orders"
readonly DLQ_NAME="orders-dlq"
readonly NOTIFIER_FUNCTION="notifier_lambda_function"
readonly NOTIFIER_LOG_GROUP="/aws/lambda/${NOTIFIER_FUNCTION}"
readonly max_attempts=20
readonly poll_interval=5

export AWS_DEFAULT_REGION="$REGION"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

command -v aws >/dev/null 2>&1 || fail "aws CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
command -v curl >/dev/null 2>&1 || fail "curl is required"

api_endpoint=$(aws apigatewayv2 get-apis \
	--query "Items[?Name=='$API_NAME'].ApiEndpoint | [0]" \
	--output text 2>/dev/null || true)

if [[ -z "$api_endpoint" || "$api_endpoint" == "None" ]]
then
	fail "HTTP API '$API_NAME' not found — apply the stack first"
fi

orders_url="${api_endpoint}/orders"
log "API endpoint: $orders_url"

# ---------------------------------------------------------------------------
# 1. Invalid payload must be rejected at ingest (HTTP 400)
# ---------------------------------------------------------------------------

log "POST /orders with an invalid payload (missing customerId)"
invalid_status=$(curl -sS -o /tmp/proj06-invalid-body.json -w "%{http_code}" \
	-X POST "$orders_url" \
	-H "Content-Type: application/json" \
	-d '{"items":[{"sku":"SKU-1","qty":1}]}')

if [[ "$invalid_status" != "400" ]]
then
	fail "Expected HTTP 400 for invalid payload, got $invalid_status"
fi
log "Invalid payload rejected with HTTP 400"

# ---------------------------------------------------------------------------
# 2. Valid order must be accepted (HTTP 202) and queued
# ---------------------------------------------------------------------------

customer_id="cust-$(date +%s)"
payload=$(jq -n \
	--arg customerId "$customer_id" \
	'{customerId: $customerId, items: [{sku: "SKU-42", qty: 2}]}')

log "POST /orders with a valid payload"
http_status=$(curl -sS -o /tmp/proj06-accept-body.json -w "%{http_code}" \
	-X POST "$orders_url" \
	-H "Content-Type: application/json" \
	-d "$payload")

if [[ "$http_status" != "202" ]]
then
	fail "Expected HTTP 202, got $http_status ($(cat /tmp/proj06-accept-body.json))"
fi

order_id=$(jq -r '.orderId // empty' /tmp/proj06-accept-body.json)
if [[ -z "$order_id" || "$order_id" == "null" ]]
then
	fail "API 202 response did not contain orderId"
fi
log "Order accepted: orderId=$order_id"

# ---------------------------------------------------------------------------
# 3. DynamoDB: poll until the processor has persisted the order
# ---------------------------------------------------------------------------

log "Waiting for the processor to write order $order_id into DynamoDB..."
attempt=1
item_found=false
while [[ $attempt -le $max_attempts ]]
do
	item=$(aws dynamodb get-item \
		--table-name "$TABLE_NAME" \
		--key "{\"PK\":{\"S\":\"ORDER#${order_id}\"},\"SK\":{\"S\":\"ORDER#${order_id}\"}}" \
		--output json 2>/dev/null || echo '{}')

	if jq -e '.Item.orderId.S' >/dev/null 2>&1 <<<"$item"
	then
		item_found=true
		log "Attempt $attempt/$max_attempts: order found in $TABLE_NAME"
		jq -c '.Item | {orderId: .orderId.S, customerId: .customerId.S, status: .status.S}' <<<"$item"
		break
	fi

	log "Attempt $attempt/$max_attempts: item not in DynamoDB yet"
	sleep "$poll_interval"
	attempt=$((attempt + 1))
done

if [[ "$item_found" != true ]]
then
	fail "Order $order_id never appeared in DynamoDB after $((max_attempts * poll_interval))s"
fi

status=$(jq -r '.Item.status.S' <<<"$item")
stored_customer=$(jq -r '.Item.customerId.S' <<<"$item")
if [[ "$status" != "PROCESSED" ]]
then
	fail "Unexpected DynamoDB status '$status' (expected PROCESSED)"
fi
if [[ "$stored_customer" != "$customer_id" ]]
then
	fail "DynamoDB customerId mismatch (got '$stored_customer')"
fi

# ---------------------------------------------------------------------------
# 4. SQS: main queue should drain; DLQ should stay empty
# ---------------------------------------------------------------------------

queue_url=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" --query QueueUrl --output text)
dlq_url=$(aws sqs get-queue-url --queue-name "$DLQ_NAME" --query QueueUrl --output text)

visible=$(aws sqs get-queue-attributes \
	--queue-url "$queue_url" \
	--attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible \
	--query Attributes \
	--output json)

log "SQS $QUEUE_NAME attributes: $(jq -c . <<<"$visible")"

dlq_visible=$(aws sqs get-queue-attributes \
	--queue-url "$dlq_url" \
	--attribute-names ApproximateNumberOfMessages \
	--query "Attributes.ApproximateNumberOfMessages" \
	--output text)

if [[ "$dlq_visible" != "0" ]]
then
	fail "DLQ $DLQ_NAME is not empty ($dlq_visible message(s))"
fi
log "DLQ $DLQ_NAME is empty"

# ---------------------------------------------------------------------------
# 5. Notifier logs: EventBridge should have invoked the notifier
# ---------------------------------------------------------------------------

log "Polling CloudWatch logs for notifier mention of order $order_id..."
start_ms=$(( ($(date +%s) - 180) * 1000 ))
attempt=1
notified=false
while [[ $attempt -le $max_attempts ]]
do
	if aws logs describe-log-groups \
		--log-group-name-prefix "$NOTIFIER_LOG_GROUP" \
		--query "logGroups[?logGroupName=='$NOTIFIER_LOG_GROUP'].logGroupName | [0]" \
		--output text 2>/dev/null | grep -q "$NOTIFIER_FUNCTION"
	then
		matches=$(aws logs filter-log-events \
			--log-group-name "$NOTIFIER_LOG_GROUP" \
			--start-time "$start_ms" \
			--filter-pattern "\"$order_id\"" \
			--query "events | length(@)" \
			--output text 2>/dev/null || echo "0")

		log "Attempt $attempt/$max_attempts: notifier log matches=$matches"
		if [[ "$matches" != "0" && "$matches" != "None" ]]
		then
			notified=true
			break
		fi
	else
		log "Attempt $attempt/$max_attempts: log group $NOTIFIER_LOG_GROUP not ready yet"
	fi
	sleep "$poll_interval"
	attempt=$((attempt + 1))
done

if [[ "$notified" != true ]]
then
	fail "Notifier logs never mentioned order $order_id — EventBridge fan-out may be broken"
fi

log "Pipeline OK for project $PROJECT (order $order_id)"
