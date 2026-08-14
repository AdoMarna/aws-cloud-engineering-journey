#!/bin/bash

set -euo pipefail

ROLE_NAME="EC2-SSM-Core-Role"
readonly INLINE_POLICY_NAME="SSM-Parameter-ReadOnly"
readonly ENV_PARAM_NAME="/config/app/env"
readonly DB_PASSWORD_PARAM_NAME="/config/app/db_password"
readonly PROJECT="proj02"
readonly ENVIRONMENT="dev"
readonly MIN_PASSWORD_LENGTH=12

# log <message>: prints a formatted status line.
log() {
	printf "==> %s\n" "$1"
}

# fail <message>: prints an error message to stderr and exits.
fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

db_password_arg="${DB_PASSWORD:-}"
if [[ -z "$db_password_arg" ]]
then
	printf "Usage: DB_PASSWORD=<db_password> %s\n" "$0" >&2
	exit 1
fi

if [[ "${#db_password_arg}" -lt "$MIN_PASSWORD_LENGTH" ]]
then
	fail "Password must be at least $MIN_PASSWORD_LENGTH characters long"
fi

if ! aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1
then
	fail "Role '$ROLE_NAME' not found. Run deploy_compute.sh before inject_config.sh"
fi

if ! aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$INLINE_POLICY_NAME" >/dev/null 2>&1
then
	fail "Inline policy '$INLINE_POLICY_NAME' missing from role '$ROLE_NAME'. Re-run deploy_compute.sh"
fi

if aws ssm get-parameter --name "$ENV_PARAM_NAME" >/dev/null 2>&1 \
	|| aws ssm get-parameter --name "$DB_PASSWORD_PARAM_NAME" --with-decryption >/dev/null 2>&1
then
	if [[ "${FORCE:-}" != "1" ]]
	then
		read -r -p "One or more parameters already exist and will be overwritten. Continue? [y/N] " confirm
		if [[ "$confirm" != "y" && "$confirm" != "Y" ]]
		then
			log "Cancelled"
			exit 0
		fi
	fi
fi

# tag_parameter <param_name>: applies the standard Project/Environment tags to an SSM parameter.
# (put-parameter --overwrite rejects --tags, so tagging is done as a separate call.)
tag_parameter() {
	local param_name="$1"
	aws ssm add-tags-to-resource \
		--resource-type "Parameter" \
		--resource-id "$param_name" \
		--tags "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENVIRONMENT" \
		>/dev/null
}

log "Publishing '$ENV_PARAM_NAME' to SSM Parameter Store"
aws ssm put-parameter \
	--name "$ENV_PARAM_NAME" \
	--type "String" \
	--value "Production" \
	--overwrite \
	>/dev/null
tag_parameter "$ENV_PARAM_NAME"

log "Publishing '$DB_PASSWORD_PARAM_NAME' to SSM Parameter Store"
aws ssm put-parameter \
	--name "$DB_PASSWORD_PARAM_NAME" \
	--type "SecureString" \
	--value "$db_password_arg" \
	--overwrite \
	>/dev/null
tag_parameter "$DB_PASSWORD_PARAM_NAME"
unset db_password_arg

log "Done"
