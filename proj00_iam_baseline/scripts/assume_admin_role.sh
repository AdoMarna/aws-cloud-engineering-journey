#!/bin/bash

set -euo pipefail

role_name="EmergencyAdminRole"
admin_policy_arn="arn:aws:iam::aws:policy/AdministratorAccess"

printf "==> Retrieving current IAM identity\n"
if ! user_arn=$(aws iam get-user --query 'User.Arn' --output text)
then
	printf "\033[31mFailure\033[0m: unable to retrieve the current IAM user.\n" >&2
	exit 1
fi

if aws iam get-role --role-name "$role_name" >/dev/null 2>&1
then
	printf "==> Role '%s' already exists, skipping creation\n" "$role_name"
else
	printf "==> Creating role '%s'\n" "$role_name"
	assume_role_policy_document=$(jq -n \
	  --arg arn "$user_arn" \
	  '{
	    Version: "2012-10-17",
	    Statement: [{
	      Effect: "Allow",
	      Principal: {AWS: $arn},
	      Action: "sts:AssumeRole"
	    }]
	  }')

	if ! aws iam create-role \
	    --role-name "$role_name" \
	    --assume-role-policy-document "$assume_role_policy_document" \
	    --max-session-duration 3600 \
	    >/dev/null
	then
		printf "\033[31mFailure\033[0m: unable to create role '%s'.\n" "$role_name" >&2
		exit 1
	fi
fi

role_arn=$(aws iam get-role \
    --role-name "$role_name" \
    --query 'Role.Arn' \
    --output text)

if aws iam list-attached-role-policies --role-name "$role_name" \
    --query "AttachedPolicies[?PolicyArn=='$admin_policy_arn'] | [0]" \
    --output text 2>/dev/null | grep -q "$admin_policy_arn"
then
	printf "==> The AdministratorAccess policy is already attached to role '%s'\n" "$role_name"
else
	printf "==> Attaching the AdministratorAccess policy to role '%s'\n" "$role_name"
	if ! aws iam attach-role-policy \
	    --role-name "$role_name" \
	    --policy-arn "$admin_policy_arn"
	then
		printf "\033[31mFailure\033[0m: unable to attach AdministratorAccess to role '%s'.\n" "$role_name" >&2
		exit 1
	fi

	printf "==> Waiting for IAM propagation\n"
	sleep 5
fi

printf "==> Assuming role to obtain temporary credentials\n"
if ! read -r AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN <<<"$(
    aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name "$role_name" \
        --duration-seconds 3600 \
        --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
        --output text
)"
then
	printf "\033[31mFailure\033[0m: unable to assume role '%s'.\n" "$role_name" >&2
	exit 1
fi

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN

printf "==> Waiting for the assumed session to propagate\n"
sleep 10

printf "\033[32mOK\033[0m: temporary credentials for '%s' exported (valid 1h).\n" "$role_name"
