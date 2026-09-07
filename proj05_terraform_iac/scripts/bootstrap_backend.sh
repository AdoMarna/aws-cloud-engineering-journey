#!/bin/bash

set -euo pipefail

readonly REGION="eu-west-3"
readonly BUCKET_NAME="shinado-proj05-private-bucket"
readonly TABLE_NAME="shinado-proj05-table"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# 1. S3 bucket: private, versioned, encrypted at rest (AES256)
# ---------------------------------------------------------------------------

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null
then
	log "Backend bucket $BUCKET_NAME already exists"
else
	log "Creating backend bucket $BUCKET_NAME in $REGION"
	aws s3api create-bucket \
		--bucket "$BUCKET_NAME" \
		--region "$REGION" \
		--create-bucket-configuration LocationConstraint="$REGION" \
		>/dev/null
	log "Backend bucket created"
fi

log "Blocking all public access on $BUCKET_NAME"
aws s3api put-public-access-block \
	--bucket "$BUCKET_NAME" \
	--public-access-block-configuration \
	BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true \
	>/dev/null

versioning_status=$(aws s3api get-bucket-versioning --bucket "$BUCKET_NAME" --query "Status" --output text 2>/dev/null || true)
if [[ "$versioning_status" == "Enabled" ]]
then
	log "Versioning already enabled on $BUCKET_NAME"
else
	log "Enabling versioning on $BUCKET_NAME"
	aws s3api put-bucket-versioning \
		--bucket "$BUCKET_NAME" \
		--versioning-configuration Status=Enabled \
		>/dev/null
fi

log "Enabling default server-side encryption (AES256) on $BUCKET_NAME"
aws s3api put-bucket-encryption \
	--bucket "$BUCKET_NAME" \
	--server-side-encryption-configuration \
	'{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
	>/dev/null

# ---------------------------------------------------------------------------
# 2. DynamoDB table: state locking (LockID primary key)
# ---------------------------------------------------------------------------

table_status=$(aws dynamodb describe-table --table-name "$TABLE_NAME" --query "Table.TableStatus" --output text 2>/dev/null || true)
if [[ -n "$table_status" && "$table_status" != "None" ]]
then
	log "Lock table $TABLE_NAME already exists"
else
	log "Creating lock table $TABLE_NAME"
	aws dynamodb create-table \
		--table-name "$TABLE_NAME" \
		--attribute-definitions AttributeName=LockID,AttributeType=S \
		--key-schema AttributeName=LockID,KeyType=HASH \
		--billing-mode PAY_PER_REQUEST \
		--tags Key=Project,Value=proj05 \
		>/dev/null
	log "Waiting for lock table to become active..."
	aws dynamodb wait table-exists --table-name "$TABLE_NAME"
	log "Lock table active"
fi

log "Backend bootstrap complete, ready for: terraform init"
