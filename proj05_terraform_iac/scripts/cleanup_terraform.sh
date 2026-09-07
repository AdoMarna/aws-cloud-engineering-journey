#!/bin/bash

set -euo pipefail

readonly REGION="eu-west-3"
readonly BUCKET_NAME="shinado-proj05-private-bucket"
readonly TABLE_NAME="shinado-proj05-table"
readonly WORKSPACE="${TF_WORKSPACE:-dev}"
readonly VAR_FILE="environments/${WORKSPACE}.tfvars"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

# ---------------------------------------------------------------------------
# 1. Destroy the full Terraform-managed stack
# ---------------------------------------------------------------------------

if [[ -f "$VAR_FILE" ]]
then
	log "Destroying Terraform stack for workspace $WORKSPACE"
	terraform destroy -auto-approve -var-file="$VAR_FILE"
	log "Stack destroyed"
else
	log "No var file for workspace $WORKSPACE, skipping terraform destroy"
fi

# ---------------------------------------------------------------------------
# 2. Empty and delete the S3 backend bucket (all versions and delete markers)
# ---------------------------------------------------------------------------

if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null
then
	log "Emptying backend bucket $BUCKET_NAME (all object versions and markers)"
	versions=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json \
		--query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')
	if [[ "$(jq -r '.Objects | length' <<<"$versions")" -gt 0 ]]
	then
		aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$versions" >/dev/null
	fi

	markers=$(aws s3api list-object-versions --bucket "$BUCKET_NAME" --output json \
		--query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')
	if [[ "$(jq -r '.Objects | length' <<<"$markers")" -gt 0 ]]
	then
		aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$markers" >/dev/null
	fi

	log "Deleting backend bucket $BUCKET_NAME"
	aws s3api delete-bucket --bucket "$BUCKET_NAME" --region "$REGION"
	log "Backend bucket deleted"
else
	log "Backend bucket $BUCKET_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 3. Delete the DynamoDB lock table
# ---------------------------------------------------------------------------

if aws dynamodb describe-table --table-name "$TABLE_NAME" >/dev/null 2>&1
then
	log "Deleting lock table $TABLE_NAME"
	aws dynamodb delete-table --table-name "$TABLE_NAME" >/dev/null
	aws dynamodb wait table-not-exists --table-name "$TABLE_NAME"
	log "Lock table deleted"
else
	log "Lock table $TABLE_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 4. Purge local Terraform working files
# ---------------------------------------------------------------------------

log "Purging local .terraform/ directory, lock file and workspace state"
rm -rf .terraform
rm -f .terraform.lock.hcl
rm -f terraform.tfstate terraform.tfstate.backup

log "Cleanup complete"
