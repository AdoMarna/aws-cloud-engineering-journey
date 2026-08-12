#!/bin/bash

set -euo pipefail

if_program_exist()
{
	local my_command
	for my_command in "$@"
	do
		if ! command -v "$my_command" &> /dev/null
		then
			printf "Program '%s' is not installed\n" "$my_command" >&2
			return 1
		fi
	done
	return 0
}

is_aws_version_2()
{
	if [[ "$(aws --version 2>&1)" =~ aws-cli/2 ]]
	then
		return 0
	fi
	return 1
}

is_aws_root()
{
	local output

	if output=$(aws sts get-caller-identity 2>/dev/null)
	then
		if jq -e '.Arn | contains ("root")' <<< "$output" >/dev/null
		then
			printf "\033[31mSecurity alert: log out of your administrator account\033[0m\n" >&2
			return 1
		fi
		return 0
	else
		printf "No user is logged in. Please log in\n" >&2
		return 1
	fi
}

check_and_hardening()
{
	local -a my_cmd=("aws" "jq" "session-manager-plugin")
	if_program_exist "${my_cmd[@]}" || exit 1
	is_aws_version_2 || exit 1
}

printf "==> Checking prerequisites\n"
check_and_hardening "$@"
printf "\033[32mOK\033[0m: prerequisites validated.\n"

group_name="Developers-Group"
user_name="dev-user-01"
profile_name="aws-dev-profile"
dev_policy_name="dev_group_policy"
mfa_policy_name="dev_group_mfa_policy"

printf "==> Switching to the temporary admin role\n"
# Sourced here (not run standalone) so the temporary AWS_* credentials are
# scoped to this script's process only and never persist in the caller's
# interactive shell. For ad-hoc admin access in your own shell, source
# scripts/assume_admin_role.sh directly instead of going through make.
source scripts/assume_admin_role.sh
is_aws_root || exit 1

printf "==> Creating group '%s'\n" "$group_name"
if aws iam get-group --group-name "$group_name" >/dev/null 2>&1
then
	printf "==> Group '%s' already exists, skipping creation\n" "$group_name"
elif ! aws iam create-group --group-name "$group_name" >/dev/null
then
	printf "\033[31mFailure\033[0m: unable to create group '%s'.\n" "$group_name" >&2
	exit 1
fi

printf "==> Creating policy '%s'\n" "$dev_policy_name"
policy_arn=$(aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='$dev_policy_name'].Arn | [0]" \
    --output text)
if [[ -z "$policy_arn" || "$policy_arn" == "None" ]]
then
	policy_arn=$(aws iam create-policy \
	    --policy-name "$dev_policy_name" \
	    --policy-document file://policies/dev_restricted_policy.json \
	    --query 'Policy.Arn' \
	    --output text)
else
	printf "==> Policy '%s' already exists, skipping creation\n" "$dev_policy_name"
fi

printf "==> Creating policy '%s'\n" "$mfa_policy_name"
mfa_policy_arn=$(aws iam list-policies --scope Local \
    --query "Policies[?PolicyName=='$mfa_policy_name'].Arn | [0]" \
    --output text)
if [[ -z "$mfa_policy_arn" || "$mfa_policy_arn" == "None" ]]
then
	mfa_policy_arn=$(aws iam create-policy \
	    --policy-name "$mfa_policy_name" \
	    --policy-document file://policies/enforce_mfa_policy.json \
	    --query 'Policy.Arn' \
	    --output text)
else
	printf "==> Policy '%s' already exists, skipping creation\n" "$mfa_policy_name"
fi

printf "==> Attaching policies to group '%s'\n" "$group_name"
aws iam attach-group-policy --group-name "$group_name" --policy-arn "$policy_arn"
aws iam attach-group-policy --group-name "$group_name" --policy-arn "$mfa_policy_arn"

printf "==> Creating user '%s'\n" "$user_name"
if aws iam get-user --user-name "$user_name" >/dev/null 2>&1
then
	printf "==> User '%s' already exists, skipping creation\n" "$user_name"
elif ! aws iam create-user --user-name "$user_name" >/dev/null
then
	printf "\033[31mFailure\033[0m: unable to create user '%s'.\n" "$user_name" >&2
	exit 1
fi

printf "==> Applying account password policy\n"
if ! aws iam update-account-password-policy \
    --minimum-password-length 16 \
    --require-symbols \
    --require-numbers \
    --require-uppercase-characters \
    --require-lowercase-characters \
    --max-password-age 90 \
    --password-reuse-prevention 5
then
	printf "\033[31mFailure\033[0m: unable to apply the password policy.\n" >&2
	exit 1
fi

printf "==> Adding '%s' to group '%s'\n" "$user_name" "$group_name"
aws iam add-user-to-group --group-name "$group_name" --user-name "$user_name"

existing_key_count=$(aws iam list-access-keys \
    --user-name "$user_name" \
    --query 'length(AccessKeyMetadata)' \
    --output text)

if [[ "$existing_key_count" -gt 0 ]]
then
	printf "==> '%s' already has an access key, skipping creation (profile '%s' should already be configured)\n" "$user_name" "$profile_name"
else
	printf "==> Creating access key for '%s'\n" "$user_name"
	read -r key_name key_secret <<<"$(
	    aws iam create-access-key \
	        --user-name "$user_name" \
	        --query '[AccessKey.AccessKeyId,AccessKey.SecretAccessKey]' \
	        --output text
	)"

	printf "==> Configuring CLI profile '%s'\n" "$profile_name"
	aws configure set aws_access_key_id \
	    "$key_name" \
	    --profile "$profile_name"

	aws configure set aws_secret_access_key \
	    "$key_secret" \
	    --profile "$profile_name"

	aws configure set region \
	    eu-west-3 \
	    --profile "$profile_name"

	printf "==> Waiting for IAM propagation of the new access key\n"
	sleep 10
fi

printf "\033[32mOK\033[0m: IAM setup complete.\n"
