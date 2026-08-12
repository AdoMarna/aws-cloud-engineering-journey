#!/bin/bash

set -euo pipefail

group_name="Developers-Group"
user_name="dev-user-01"
profile_name="aws-dev-profile"
role_name="EmergencyAdminRole"
dev_policy_name="dev_group_policy"
mfa_policy_name="dev_group_mfa_policy"
admin_policy_arn="arn:aws:iam::aws:policy/AdministratorAccess"

error_count=0

run_step()
{
	local description="$1"
	shift

	printf "==> %s\n" "$description"
	if "$@" >/dev/null 2>&1
	then
		printf "\033[32mOK\033[0m: %s\n" "$description"
	else
		printf "\033[31mFAILED\033[0m: %s\n" "$description" >&2
		error_count=$((error_count + 1))
	fi
}

printf "==> Looking up policies '%s' and '%s'\n" "$dev_policy_name" "$mfa_policy_name"
policy_arn=$(aws iam list-policies --scope Local \
	--query "Policies[?PolicyName=='$dev_policy_name'].Arn | [0]" \
	--output text)

mfa_policy_arn=$(aws iam list-policies --scope Local \
	--query "Policies[?PolicyName=='$mfa_policy_name'].Arn | [0]" \
	--output text)

if [[ -z "$policy_arn" || "$policy_arn" == "None" ]]
then
	printf "\033[33mWarning\033[0m: policy '%s' not found, detach/delete step will be skipped.\n" "$dev_policy_name" >&2
	policy_arn=""
fi

if [[ -z "$mfa_policy_arn" || "$mfa_policy_arn" == "None" ]]
then
	printf "\033[33mWarning\033[0m: policy '%s' not found, detach/delete step will be skipped.\n" "$mfa_policy_name" >&2
	mfa_policy_arn=""
fi

printf "==> Looking up the access key for user '%s'\n" "$user_name"
access_key_id=$(aws iam list-access-keys --user-name "$user_name" \
	--query 'AccessKeyMetadata[0].AccessKeyId' \
	--output text 2>/dev/null || true)

if [[ -z "$access_key_id" || "$access_key_id" == "None" ]]
then
	printf "\033[33mWarning\033[0m: no access key found for '%s'.\n" "$user_name" >&2
	access_key_id=""
fi

run_step "Removing the local access key from profile '$profile_name'" \
	aws configure --profile "$profile_name" set aws_access_key_id ""

run_step "Deleting the IAM access key for user '$user_name'" \
	aws iam delete-access-key --user-name "$user_name" --access-key-id "$access_key_id"

run_step "Deleting the account password policy" \
	aws iam delete-account-password-policy

run_step "Removing user '$user_name' from group '$group_name'" \
	aws iam remove-user-from-group --group-name "$group_name" --user-name "$user_name"

run_step "Detaching policy '$dev_policy_name' from group '$group_name'" \
	aws iam detach-group-policy --group-name "$group_name" --policy-arn "$policy_arn"

run_step "Detaching policy '$mfa_policy_name' from group '$group_name'" \
	aws iam detach-group-policy --group-name "$group_name" --policy-arn "$mfa_policy_arn"

run_step "Detaching policy AdministratorAccess from role '$role_name'" \
	aws iam detach-role-policy --role-name "$role_name" --policy-arn "$admin_policy_arn"

run_step "Deleting policy '$dev_policy_name'" \
	aws iam delete-policy --policy-arn "$policy_arn"

run_step "Deleting policy '$mfa_policy_name'" \
	aws iam delete-policy --policy-arn "$mfa_policy_arn"

run_step "Deleting role '$role_name'" \
	aws iam delete-role --role-name "$role_name"

run_step "Deleting user '$user_name'" \
	aws iam delete-user --user-name "$user_name"

run_step "Deleting group '$group_name'" \
	aws iam delete-group --group-name "$group_name"

unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

printf "\n"
if ((error_count == 0))
then
	printf "\033[32mCleanup completed without errors.\033[0m\n"
else
	printf "\033[31mCleanup completed with %d error(s). Check the state of the IAM resources.\033[0m\n" "$error_count" >&2
	exit 1
fi
