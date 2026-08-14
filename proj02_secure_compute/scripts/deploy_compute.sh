#!/bin/bash

set -euo pipefail

readonly ROLE_NAME="EC2-SSM-Core-Role"
readonly SSM_POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
readonly CLOUDWATCH_POLICY_ARN="arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
readonly INLINE_POLICY_NAME="SSM-Parameter-ReadOnly"
readonly INSTANCE_PROFILE_NAME="EC2-SSM-Instance-Profile"
readonly PROJECT="proj02"
readonly ENVIRONMENT="dev"
readonly port=80
readonly ENV_PARAM_NAME="/config/app/env"
readonly DB_PASSWORD_PARAM_NAME="/config/app/db_password"
vpc_id=$(aws ec2 describe-vpcs --filter "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)
private_sub_id_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ1" --query "Subnets[0].SubnetId" --output text)
private_sub_id_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ2" --query "Subnets[0].SubnetId" --output text)


# log <message>: prints a formatted status line.
log() {
	printf "==> %s\n" "$1"
}

# fail <message>: prints an error message to stderr and exits.
fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

jq_field() {
	local json="$1" filter="$2"
	jq -r "$filter // empty" <<<"$json"
}

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1
then
	log "Role '$ROLE_NAME' already exists, skipping creation"
else
	aws iam create-role \
		--role-name "$ROLE_NAME" \
		--assume-role-policy-document "file://templates/ssm_trust_policy.json" \
		--tags "[{\"Key\": \"Name\", \"Value\": \"$ROLE_NAME\"}, {\"Key\": \"Project\", \"Value\": \"$PROJECT\"}, {\"Key\": \"Environment\", \"Value\": \"$ENVIRONMENT\"}]" \
		>/dev/null
	log "Role '$ROLE_NAME' have been created"
fi

attached_arn=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
	--query "AttachedPolicies[?PolicyArn=='$SSM_POLICY_ARN'] | [0].PolicyArn" \
	--output text 2>/dev/null || true)

if [[ "$attached_arn" == "$SSM_POLICY_ARN" ]]
then
	log "SSMManagedInstanceCore policy is already attached to role '$ROLE_NAME'"
else
	log "Attaching SSMManagedInstanceCore policy to role '$ROLE_NAME'"
	aws iam attach-role-policy \
		--role-name "$ROLE_NAME" \
		--policy-arn "$SSM_POLICY_ARN" \
		>/dev/null
fi

attached_cw_arn=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
	--query "AttachedPolicies[?PolicyArn=='$CLOUDWATCH_POLICY_ARN'] | [0].PolicyArn" \
	--output text 2>/dev/null || true)

if [[ "$attached_cw_arn" == "$CLOUDWATCH_POLICY_ARN" ]]
then
	log "CloudWatchAgentServerPolicy is already attached to role '$ROLE_NAME'"
else
	log "Attaching CloudWatchAgentServerPolicy to role '$ROLE_NAME'"
	aws iam attach-role-policy \
		--role-name "$ROLE_NAME" \
		--policy-arn "$CLOUDWATCH_POLICY_ARN" \
		>/dev/null
fi

account_id=$(aws sts get-caller-identity --query Account --output text)
region=$(aws configure get region)

log "Attaching inline policy '$INLINE_POLICY_NAME' to role '$ROLE_NAME'"
aws iam put-role-policy \
	--role-name "$ROLE_NAME" \
	--policy-name "$INLINE_POLICY_NAME" \
	--policy-document "$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "ssm:GetParameter",
        "Resource": [
          "arn:aws:ssm:${region}:${account_id}:parameter${ENV_PARAM_NAME}",
          "arn:aws:ssm:${region}:${account_id}:parameter${DB_PASSWORD_PARAM_NAME}"
        ]
      },
      {
        "Effect": "Allow",
        "Action": "kms:Decrypt",
        "Resource": "arn:aws:kms:${region}:${account_id}:alias/aws/ssm"
      }
    ]
}
EOF
)" \
	>/dev/null

log "Waiting for IAM role propagation"
iam_propagation_attempts=0
until aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$INLINE_POLICY_NAME" >/dev/null 2>&1
do
	iam_propagation_attempts=$((iam_propagation_attempts + 1))
	if [[ "$iam_propagation_attempts" -ge 12 ]]
	then
		fail "Inline policy '$INLINE_POLICY_NAME' still not visible on role '$ROLE_NAME' after 60s"
	fi
	log "Inline policy '$INLINE_POLICY_NAME' not visible yet, retrying..."
	sleep 5
done
sleep 10

if aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" >/dev/null 2>&1
then
	log "Instance profile '$INSTANCE_PROFILE_NAME' already exists, skipping creation"
else
	log "Creating instance profile '$INSTANCE_PROFILE_NAME'"
	aws iam create-instance-profile \
		--instance-profile-name "$INSTANCE_PROFILE_NAME" \
		>/dev/null
fi

role_in_profile=$(aws iam get-instance-profile --instance-profile-name "$INSTANCE_PROFILE_NAME" \
	--query "InstanceProfile.Roles[?RoleName=='$ROLE_NAME'] | [0].RoleName" --output text)

if [[ "$role_in_profile" != "$ROLE_NAME" ]]
then
	log "Attaching role '$ROLE_NAME' to instance profile '$INSTANCE_PROFILE_NAME'"
	aws iam add-role-to-instance-profile \
		--role-name "$ROLE_NAME" \
		--instance-profile-name "$INSTANCE_PROFILE_NAME" \
		>/dev/null
	aws iam tag-instance-profile \
		--instance-profile-name "$INSTANCE_PROFILE_NAME" \
		--tags "[{\"Key\": \"Name\", \"Value\": \"$INSTANCE_PROFILE_NAME\"}, {\"Key\": \"Project\", \"Value\": \"$PROJECT\"}, {\"Key\": \"Environment\", \"Value\": \"$ENVIRONMENT\"}]" \
		>/dev/null

	log "Waiting for instance profile propagation"
	sleep 15
else
	log "Role '$ROLE_NAME' already attached to instance profile '$INSTANCE_PROFILE_NAME'"
fi

SG_id=$(aws ec2 describe-security-groups --filter "Name=tag:Name,Values=My Security Group" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_id" || "$SG_id" == "None" ]]
then
	log "Creating security group"
	SG_id=$(aws ec2 create-security-group --group-name SG --description "SG - trafic depuis SG vers local" --vpc-id "$vpc_id" --tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=My Security Group},{Key=Project,Value=proj02},{Key=Environment,Value=dev}]' --query GroupId --output text)
else
	log "Security group already created, skipping"
fi
json=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_id" --output json)
SG_rules_SG_id=$(jq_field "$json" \
	".SecurityGroupRules[] | select(.IsEgress==false and .FromPort==$port and .ToPort==$port and .CidrIpv4==\"10.0.0.0/16\") | .SecurityGroupRuleId")
if [[ -z "$SG_rules_SG_id" ]]
then
	log "Creating security group rules"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_id" \
		--protocol tcp \
		--port "$port" \
		--cidr 10.0.0.0/16 \
		--tag-specifications ResourceType=security-group-rule,Tags='[{Key=Name,Value=My Security Group Rules},{Key=Project,Value=proj02},{Key=Environment,Value=dev}]' >/dev/null
else
	log "Security group rules already in place, skipping"
fi

instance_id_one=$(aws ec2 describe-instances --filters Name="tag:Name",Values="my_instance_one" Name="instance-state-name",Values="pending,running,stopping,stopped" --query Reservations[0].Instances[0].InstanceId --output text)
if [[ -z "$instance_id_one" || "$instance_id_one" == "None" ]]
then
	log "Creating my_instance_one"
	aws ec2 run-instances \
		--image-id \
			resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
		--instance-type t3.micro \
		--region "$region" \
		--subnet-id "$private_sub_id_one" \
		--security-group-ids "$SG_id" \
		--metadata-options "InstanceMetadataTags=enabled" \
		--metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=my_instance_one}, {Key=Project,Value=proj02}, {Key=Environment,Value=dev}]" \
		--user-data file://templates/userdata.sh \
		--iam-instance-profile "Name=$INSTANCE_PROFILE_NAME" \
		>/dev/null
else
	log "my_instance_one already exists, skipping"
fi

instance_id_two=$(aws ec2 describe-instances --filters Name="tag:Name",Values="my_instance_two" Name="instance-state-name",Values="pending,running,stopping,stopped" --query Reservations[0].Instances[0].InstanceId --output text)
if [[ -z "$instance_id_two" || "$instance_id_two" == "None" ]]
then
	log "Creating my_instance_two"
	aws ec2 run-instances \
		--image-id \
			resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
		--instance-type t3.micro \
		--region "$region" \
		--subnet-id "$private_sub_id_two" \
		--security-group-ids "$SG_id" \
		--metadata-options "InstanceMetadataTags=enabled" \
		--metadata-options "HttpEndpoint=enabled,HttpTokens=required,HttpPutResponseHopLimit=2" \
		--tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=my_instance_two}, {Key=Project,Value=proj02}, {Key=Environment,Value=dev}]" \
		--user-data file://templates/userdata.sh \
		--iam-instance-profile "Name=$INSTANCE_PROFILE_NAME" \
		>/dev/null
else
	log "my_instance_two already exists, skipping"
fi

db_password=$(openssl rand -base64 18)
DB_PASSWORD="$db_password" bash scripts/inject_config.sh
unset db_password

log "Waiting for instances to register as SSM managed nodes"
for name in my_instance_one my_instance_two
do
	instance_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="$name" Name="instance-state-name",Values="pending,running" --query "Reservations[0].Instances[0].InstanceId" --output text)
	ssm_registration_attempts=0
	until aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$instance_id" --query "InstanceInformationList[0].PingStatus" --output text 2>/dev/null | grep -q "Online"
	do
		ssm_registration_attempts=$((ssm_registration_attempts + 1))
		if [[ "$ssm_registration_attempts" -ge 18 ]]
		then
			fail "'$name' never registered as an SSM managed node after 3 minutes"
		fi
		log "Waiting for '$name'  to become visible to SSM..."
		sleep 10
	done
done

log "Waiting for SSM agent/IAM permissions to fully settle before running SSM documents"
sleep 20

readonly PATCH_BASELINE_NAME="proj02-al2023-baseline"
readonly PATCH_GROUP="proj02-dev"
readonly INVENTORY_ASSOCIATION_NAME="proj02-inventory-collection"
readonly PATCH_SCAN_ASSOCIATION_NAME="proj02-patch-scan"

patch_baseline_id=$(aws ssm describe-patch-baselines \
	--filters "Key=OWNER,Values=Self" \
	--query "BaselineIdentities[?BaselineName=='$PATCH_BASELINE_NAME'].BaselineId | [0]" \
	--output text 2>/dev/null || true)

if [[ -z "$patch_baseline_id" || "$patch_baseline_id" == "None" ]]
then
	log "Creating Patch Baseline '$PATCH_BASELINE_NAME'"
	patch_baseline_id=$(aws ssm create-patch-baseline \
		--name "$PATCH_BASELINE_NAME" \
		--operating-system "AMAZON_LINUX_2023" \
		--description "proj02 patch baseline - inherits from the default AWS AL2023 baseline" \
		--approval-rules "PatchRules=[{PatchFilterGroup={PatchFilters=[{Key=CLASSIFICATION,Values=[Security,Bugfix]},{Key=SEVERITY,Values=[Critical,Important]}]},ApproveAfterDays=0,ComplianceLevel=CRITICAL}]" \
		--tags "Key=Name,Value=$PATCH_BASELINE_NAME" "Key=Project,Value=$PROJECT" "Key=Environment,Value=$ENVIRONMENT" \
		--query "BaselineId" \
		--output text)
else
	log "Patch Baseline '$PATCH_BASELINE_NAME' already exists, skipping"
fi

log "Registering Patch Group '$PATCH_GROUP' on the baseline"
aws ssm register-patch-baseline-for-patch-group \
	--baseline-id "$patch_baseline_id" \
	--patch-group "$PATCH_GROUP" \
	>/dev/null

for name in my_instance_one my_instance_two
do
	instance_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="$name" Name="instance-state-name",Values="pending,running" --query "Reservations[0].Instances[0].InstanceId" --output text)

	tag_value=$(aws ec2 describe-tags --filters "Name=resource-id,Values=$instance_id" "Name=key,Values=Patch Group" --query "Tags[0].Value" --output text 2>/dev/null || true)
	if [[ "$tag_value" != "$PATCH_GROUP" ]]
	then
		log "Tagging '$name' with 'Patch Group=$PATCH_GROUP'"
		aws ec2 create-tags --resources "$instance_id" --tags "Key=Patch Group,Value=$PATCH_GROUP" >/dev/null
	fi
done

association_exists() {
	local association_name="$1"
	local found
	found=$(aws ssm list-associations \
		--association-filter-list "key=AssociationName,value=$association_name" \
		--query "Associations[0].AssociationId" --output text 2>/dev/null || true)
	[[ -n "$found" && "$found" != "None" ]]
}

if association_exists "$INVENTORY_ASSOCIATION_NAME"
then
	log "Inventory association '$INVENTORY_ASSOCIATION_NAME' already exists, skipping"
else
	log "Creating SSM Inventory association '$INVENTORY_ASSOCIATION_NAME'"
	aws ssm create-association \
		--name "AWS-GatherSoftwareInventory" \
		--association-name "$INVENTORY_ASSOCIATION_NAME" \
		--targets "Key=tag:Project,Values=$PROJECT" \
		--schedule-expression "rate(30 minutes)" \
		>/dev/null
fi

if association_exists "$PATCH_SCAN_ASSOCIATION_NAME"
then
	log "Patch Manager association '$PATCH_SCAN_ASSOCIATION_NAME' already exists, skipping"
else
	log "Creating Patch Manager (scan) association '$PATCH_SCAN_ASSOCIATION_NAME'"
	aws ssm create-association \
		--name "AWS-RunPatchBaseline" \
		--association-name "$PATCH_SCAN_ASSOCIATION_NAME" \
		--targets "Key=tag:Project,Values=$PROJECT" \
		--parameters "Operation=Scan" \
		--schedule-expression "rate(1 day)" \
		>/dev/null
fi

log "Waiting for the association-triggered patch scan to complete"

for name in my_instance_one my_instance_two
do
	instance_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="$name" Name="instance-state-name",Values="pending,running" --query "Reservations[0].Instances[0].InstanceId" --output text)

	patch_scan_wait_attempts=0
	until aws ssm describe-instance-associations-status --instance-id "$instance_id" \
		--query "InstanceAssociationStatusInfos[?AssociationName=='$PATCH_SCAN_ASSOCIATION_NAME'] | [0].Status" \
		--output text 2>/dev/null | grep -qE '^(Success|Failed)$'
	do
		patch_scan_wait_attempts=$((patch_scan_wait_attempts + 1))
		if [[ "$patch_scan_wait_attempts" -ge 18 ]]
		then
			log "'$name': association-triggered scan did not report completion after 3 minutes, continuing anyway"
			break
		fi
		log "Waiting for '$name' patch association to run..."
		sleep 10
	done
done

log "Patch compliance report (describe-instance-patch-states)"
instance_ids=$(aws ec2 describe-instances \
	--filters "Name=tag:Project,Values=$PROJECT" "Name=instance-state-name,Values=pending,running" \
	--query "Reservations[].Instances[].InstanceId" \
	--output text)

aws ssm describe-instance-patch-states \
	--instance-ids $instance_ids \
	--output json \
	>/dev/null