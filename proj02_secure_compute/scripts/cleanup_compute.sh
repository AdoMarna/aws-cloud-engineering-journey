#!/bin/bash

set -euo pipefail

readonly ROLE_NAME="EC2-SSM-Core-Role"
readonly SSM_POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
readonly CLOUDWATCH_POLICY_ARN="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
readonly INLINE_POLICY_NAME="SSM-Parameter-ReadOnly"
readonly ENV_PARAM_NAME="/config/app/env"
readonly DB_PASSWORD_PARAM_NAME="/config/app/db_password"
readonly INSTANCE_PROFILE_NAME="EC2-SSM-Instance-Profile"
readonly PROJECT="proj02"
readonly ENVIRONMENT="dev"
readonly port=80
readonly PATCH_BASELINE_NAME="proj02-al2023-baseline"
readonly PATCH_GROUP="proj02-dev"
readonly INVENTORY_ASSOCIATION_NAME="proj02-inventory-collection"
readonly PATCH_SCAN_ASSOCIATION_NAME="proj02-patch-scan"

# log <message>: prints a formatted status line.
log() {
	printf "==> %s\n" "$1"
}

# fail <message>: prints an error message to stderr and exits.
fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

if [[ "${FORCE:-}" != "1" ]]
then
	read -r -p "This will destroy the compute resources of project '$PROJECT' ($ENVIRONMENT). Continue? [y/N] " confirm
	if [[ "$confirm" != "y" && "$confirm" != "Y" ]]
	then
		log "Cancelled"
		exit 0
	fi
fi

SG_id=$(aws ec2 describe-security-groups --filter "Name=tag:Name,Values=My Security Group" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)

for association_name in "$INVENTORY_ASSOCIATION_NAME" "$PATCH_SCAN_ASSOCIATION_NAME"
do
	association_ids=$(aws ssm list-associations \
		--association-filter-list "key=AssociationName,value=$association_name" \
		--query "Associations[].AssociationId" --output text 2>/dev/null || true)

	if [[ -z "$association_ids" ]]
	then
		log "SSM association '$association_name' not found, skipping"
	else
		for association_id in $association_ids
		do
			log "Deleting SSM association '$association_name'"
			aws ssm delete-association --association-id "$association_id"
		done
	fi
done

patch_baseline_id=$(aws ssm describe-patch-baselines \
	--filters "Key=OWNER,Values=Self" \
	--query "BaselineIdentities[?BaselineName=='$PATCH_BASELINE_NAME'].BaselineId | [0]" \
	--output text 2>/dev/null || true)

if [[ -n "$patch_baseline_id" && "$patch_baseline_id" != "None" ]]
then
	log "Deregistering Patch Group '$PATCH_GROUP'"
	aws ssm deregister-patch-baseline-for-patch-group \
		--baseline-id "$patch_baseline_id" \
		--patch-group "$PATCH_GROUP" \
		2>/dev/null || true

	log "Deleting Patch Baseline '$PATCH_BASELINE_NAME'"
	aws ssm delete-patch-baseline --baseline-id "$patch_baseline_id"
else
	log "Patch Baseline '$PATCH_BASELINE_NAME' not found, skipping"
fi

for name in my_instance_one my_instance_two
do
	instance_id=$(aws ec2 describe-instances \
		--filters Name="tag:Name",Values="$name" Name="instance-state-name",Values="pending,running,stopping,stopped" \
		--query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null || true)

	if [[ -z "$instance_id" || "$instance_id" == "None" ]]
	then
		log "Instance '$name' not found or already terminated, skipping"
	else
		log "Terminating instance '$name'"
		aws ec2 terminate-instances --instance-ids "$instance_id" >/dev/null
		log "Waiting for '$name' to terminate"
		aws ec2 wait instance-terminated --instance-ids "$instance_id"
	fi
done

if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1
then
	if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" \
		--query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME'] | [0]" --output text 2>/dev/null | grep -q "$ROLE_NAME"
	then
		log "Detaching role '$ROLE_NAME' from instance profile '$INSTANCE_PROFILE_NAME'"
		aws iam remove-role-from-instance-profile \
			--instance-profile-name "$INSTANCE_PROFILE_NAME" \
			--role-name "$ROLE_NAME"
	fi

	log "Deleting instance profile '$INSTANCE_PROFILE_NAME'"
	aws iam delete-instance-profile \
		--instance-profile-name "$INSTANCE_PROFILE_NAME"
else
	log "Instance profile '$INSTANCE_PROFILE_NAME' not found, skipping"
fi

if [[ -z "$SG_id" || "$SG_id" == "None" ]]
then
	log "Security group not found, skipping"
else
	rule_id=$(aws ec2 describe-security-group-rules \
		--filters "Name=group-id,Values=$SG_id" \
		--query "SecurityGroupRules[?IsEgress==\`false\` && FromPort==\`$port\` && ToPort==\`$port\` && CidrIpv4=='10.0.0.0/16'] | [0].SecurityGroupRuleId" \
		--output text 2>/dev/null || true)

	if [[ -n "$rule_id" && "$rule_id" != "None" ]]
	then
		log "Revoking ingress rule on security group SG"
		aws ec2 revoke-security-group-ingress \
			--group-id "$SG_id" \
			--protocol tcp \
			--port "$port" \
			--cidr 10.0.0.0/16 \
			2>/dev/null
	fi

	log "Deleting security group SG"
	aws ec2 delete-security-group --group-id "$SG_id"
fi

for param_name in "$ENV_PARAM_NAME" "$DB_PASSWORD_PARAM_NAME"
do
	if aws ssm get-parameter --name "$param_name" >/dev/null 2>&1
	then
		log "Deleting SSM parameter '$param_name'"
		aws ssm delete-parameter --name "$param_name"
	else
		log "SSM parameter '$param_name' not found, skipping"
	fi
done

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1
then
	for policy_arn in "$SSM_POLICY_ARN" "$CLOUDWATCH_POLICY_ARN"
	do
		attached_arn=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
			--query "AttachedPolicies[?PolicyArn=='$policy_arn'] | [0].PolicyArn" \
			--output text 2>/dev/null || true)

		if [[ "$attached_arn" == "$policy_arn" ]]
		then
			log "Detaching policy '$policy_arn' from role '$ROLE_NAME'"
			aws iam detach-role-policy \
				--role-name "$ROLE_NAME" \
				--policy-arn "$policy_arn"
		fi
	done

	if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$INLINE_POLICY_NAME" >/dev/null 2>&1
	then
		log "Deleting inline policy '$INLINE_POLICY_NAME' from role '$ROLE_NAME'"
		aws iam delete-role-policy \
			--role-name "$ROLE_NAME" \
			--policy-name "$INLINE_POLICY_NAME"
	fi

	log "Deleting role '$ROLE_NAME'"
	aws iam delete-role \
		--role-name "$ROLE_NAME"
else
	log "Role '$ROLE_NAME' not found, skipping"
fi
