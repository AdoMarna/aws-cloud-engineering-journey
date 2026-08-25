#!/bin/bash

set -euo pipefail

readonly port=80
readonly INSTANCE_PROFILE_NAME="EC2-SSM-Instance-Profile"

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)
if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	exit 1
fi

subnet_pub_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ1" --query "Subnets[0].SubnetId" --output text)
subnet_pub_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ2" --query "Subnets[0].SubnetId" --output text)
subnet_priv_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ1" --query "Subnets[0].SubnetId" --output text)
subnet_priv_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ2" --query "Subnets[0].SubnetId" --output text)
image_id=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query "Parameter.Value" --output text)

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

jq_field() {
	local json="$1" filter="$2"
	jq -r "$filter // empty" <<<"$json"
}

SG_ALB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG ALB" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_ALB_id" || "$SG_ALB_id" == "None" ]]
then
	log "Security Group ALB is created"
	SG_ALB_id=$(aws ec2 create-security-group \
		--group-name SG-ALB \
		--vpc-id "$vpc_id" \
		--description "SG-ALB - public HTTP/HTTPS traffic to ALB"\
		--tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=SG ALB},{Key=Project,Value=proj03},{Key=Environment,Value=dev}]' \
		--query GroupId \
		--output text)
else
	log "SG ALB already exist"
fi

json=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ALB_id" --output json)
SG_ALB_rules_id=$(jq_field "$json" \
	".SecurityGroupRules[] | select(.IsEgress==false and .FromPort==$port and .ToPort==$port and .CidrIpv4==\"0.0.0.0/0\") | .SecurityGroupRuleId")
if [[ -z "$SG_ALB_rules_id" ]]
then
	log "Creating ALB security group rules"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_ALB_id" \
		--port "$port" \
		--protocol tcp \
		--cidr 0.0.0.0/0 \
		>/dev/null
else
	log "SG ALB rules already exist"
fi

SG_App_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG App" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_App_id" || "$SG_App_id" == "None" ]]
then
	log "Security Group App is created"
	SG_App_id=$(aws ec2 create-security-group \
		--group-name SG-App \
		--vpc-id "$vpc_id" \
		--tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=SG App},{Key=Project,Value=proj03},{Key=Environment,Value=dev}]' \
		--description "SG-App - traffic from SG-ALB to application" \
		--query GroupId \
		--output text)
else
	log "SG App already exist"
fi

json_tmp=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_App_id" --output json)
SG_App_rules_id=$(jq_field "$json_tmp" \
	".SecurityGroupRules[] | select(.IsEgress==false and .FromPort==$port and .ToPort==$port) | .SecurityGroupRuleId")
if [[ -z "$SG_App_rules_id" ]]
then
	log "Create SG App rules"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_App_id" \
		--source-group "$SG_ALB_id" \
		--port 80 \
		--protocol tcp \
		>/dev/null
else
	log "SG App rules already exist"
fi

template_id=$(aws ec2 describe-launch-templates --filters "Name=tag:Project,Values=proj03" "Name=tag:Name,Values=my_lt" --query LaunchTemplates[0].LaunchTemplateId --output text)
if [[ -z "$template_id" || "$template_id" == "None" ]]
then
	log "Filling json file"
	userdata_b64=$(base64 -w0 templates/userdata.sh)
	jq --arg profile "$INSTANCE_PROFILE_NAME" \
	--arg image "$image_id" \
	--arg sg1 "$SG_ALB_id" \
	--arg sg2 "$SG_App_id" \
	--arg ud "$userdata_b64" \
	'.IamInstanceProfile.Name = $profile
		| .ImageId = $image
		| .SecurityGroupIds = [$sg1, $sg2]
		| .UserData = $ud' \
	templates/launch_template.json > templates/launch_template.json.tmp \
	&& mv templates/launch_template.json.tmp templates/launch_template.json
	log "Create launch template"
	template_id=$(aws ec2 create-launch-template \
	--launch-template-name my_template \
	--version-description LocalVersion1 \
	--launch-template-data file://templates/launch_template.json \
	--tag-specifications ResourceType=launch-template,Tags='[{Key=Name,Value=my_lt},{Key=Project,Value=proj03},{Key=Environment,Value=dev}]' \
	--query LaunchTemplateId \
	--output text)
	log "Launch template created"
else
	log "Launch template already created"
fi

target_group_arn=$(aws elbv2 describe-target-groups --names my-tg --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
if [[ -z "$target_group_arn" || "$target_group_arn" == "None" ]]
then
	log "Create target group"
	target_group_arn=$(aws elbv2 create-target-group \
		--name my-tg \
		--protocol HTTP \
		--port 80 \
		--target-type instance \
		--vpc-id "$vpc_id" \
		--health-check-port 80 \
		--healthy-threshold-count 2 \
		--health-check-interval 15 \
		--health-check-path "/" \
		--tags Key=Name,Value=my-tg Key=Project,Value=proj03 Key=Environment,Value=dev \
		--query TargetGroups[0].TargetGroupArn \
		--output text)
	log "Target group is created"
else
	log "Target group already exists"
fi

load_balancer_arn=$(aws elbv2 describe-load-balancers --names my-load-balancer --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)
if [[ -z "$load_balancer_arn" || "$load_balancer_arn" == "None" ]]
then
	log "Create load balancer"
	load_balancer_arn=$(aws elbv2 create-load-balancer \
		--name my-load-balancer \
		--type application \
		--subnets "$subnet_pub_one" "$subnet_pub_two" \
		--security-groups "$SG_ALB_id" \
		--tags Key=Name,Value=my_load_balancer Key=Project,Value=proj03 Key=Environment,Value=dev \
		--query LoadBalancers[0].LoadBalancerArn \
		--output text)
	log "Load balancer created, waiting for it to become active (can take a couple minutes)..."
	aws elbv2 wait load-balancer-available --load-balancer-arns "$load_balancer_arn"
	log "Load balancer is active"
else
	log "Load balancer already exists"
fi

listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$load_balancer_arn" --query "Listeners[0].ListenerArn" --output text 2>/dev/null || true)
if [[ -z "$listener_arn" || "$listener_arn" == "None" ]]
then
	log "Create listener"
	listener_arn=$(aws elbv2 create-listener \
		--load-balancer-arn "$load_balancer_arn" \
		--protocol HTTP \
		--port 80 \
		--default-actions Type=forward,TargetGroupArn="$target_group_arn" \
		--query Listeners[0].ListenerArn \
		--output text)
	aws elbv2 add-tags \
		--resource-arns "$listener_arn" \
		--tags Key=Name,Value=my_listener Key=Project,Value=proj03 Key=Environment,Value=dev \
		>/dev/null
	log "Listener created"
else
	log "Listener already exists"
fi
log "Waiting for propagation"
sleep 15
asg_name=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my_asg --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || true)
if [[ -z "$asg_name" || "$asg_name" == "None" ]]
then
	aws autoscaling create-auto-scaling-group \
		--auto-scaling-group-name my_asg \
		--launch-template LaunchTemplateId="$template_id" \
		--target-group-arns "$target_group_arn" \
		--health-check-type ELB \
		--health-check-grace-period 600 \
		--min-size 2 \
		--max-size 4 \
		--desired-capacity 2 \
		--vpc-zone-identifier "$subnet_priv_one,$subnet_priv_two" \
		--tags "ResourceId=my_asg,ResourceType=auto-scaling-group,Key=Name,Value=my_asg,PropagateAtLaunch=true" \
		"ResourceId=my_asg,ResourceType=auto-scaling-group,Key=Project,Value=proj03,PropagateAtLaunch=true" \
		"ResourceId=my_asg,ResourceType=auto-scaling-group,Key=Environment,Value=dev,PropagateAtLaunch=true"
	log "Auto Scaling Group created, waiting for the 2 instances to become healthy behind the Target Group (can take several minutes)..."
	aws elbv2 wait target-in-service --target-group-arn "$target_group_arn"
	log "Auto Scaling Group is stable and healthy"
else
	log "Auto Scaling Group already exists"
fi

# bash scripts/enable_autoscalling_policy.sh
# bash scripts/stress_test.sh