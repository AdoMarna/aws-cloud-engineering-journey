#!/bin/bash

set -euo pipefail

readonly REGION="${AWS_REGION:-eu-west-3}"
readonly ROLE_NAME="ecsTaskExecutionRole"
readonly POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
readonly LOG_GROUP_NAME_APP="/ecs/proj04-app"
readonly LOG_GROUP_NAME_API="/ecs/proj04-api"
readonly CLUSTER_NAME="proj04-cluster"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text 2>/dev/null || true)
if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	log "VPC does not exist, nothing to clean up on the network side"
fi

SG_ALB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG ALB" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
SG_App_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG App" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
target_group_app_arn=$(aws elbv2 describe-target-groups --names my-ip-tg-two --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
target_group_api_arn=$(aws elbv2 describe-target-groups --names my-ip-tg-one --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
lb_arn=$(aws elbv2 describe-load-balancers --names my-load-balancer --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)
listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$lb_arn" --query "Listeners[0].ListenerArn" --output text 2>/dev/null || true)
aws_id=$(aws sts get-caller-identity --query Account --output text)
ecr_uri_app="$aws_id.dkr.ecr.$REGION.amazonaws.com/proj04-app"
ecr_uri_api="$aws_id.dkr.ecr.$REGION.amazonaws.com/proj04-api"
image_app="$ecr_uri_app:local"
image_api="$ecr_uri_api:local"

# ---------------------------------------------------------------------------
# 1. ECS services: scale to 0, wait, then delete
# ---------------------------------------------------------------------------

scale_down_and_delete_service() {
	local service_name="$1"
	local resource="service/proj04-cluster/$service_name"
	local status
	local policy
	local target
	
	status=$(aws ecs describe-services \
		--cluster "$CLUSTER_NAME" \
		--services "$service_name" \
		--query "services[0].status" \
		--output text 2>/dev/null || true)

	if [[ -z "$status" || "$status" == "None" || "$status" == "INACTIVE" ]]
	then
		log "Service $service_name already gone"
		return
	fi

	policy_check=$(aws application-autoscaling describe-scaling-policies \
		--service-namespace ecs \
		--resource-id "$resource" \
		--query ScalingPolicies[0].PolicyName \
		--output text)
	if [[ -n "$policy_check" || "$policy_check" != "None" ]]
	then
		log "Delete policy"
		aws application-autoscaling delete-scaling-policy \
			--service-namespace ecs \
			--scalable-dimension ecs:service:DesiredCount \
			--resource-id "$resource" \
			--policy-name cpu60-target-tracking-scaling-policy \
			>/dev/null
	fi

	target_scalable_arn=$(aws application-autoscaling describe-scalable-targets \
		--service-namespace ecs \
		--resource-id "$resource" \
		--query ScalableTargets[0].ScalableTargetARN \
		--output text 2>/dev/null || true)
	if [[ -n "$target_scalable_arn" || "$target_scalable_arn" != "None" ]]
	then
		log "Deregister scalable target"
		aws application-autoscaling deregister-scalable-target \
			--service-namespace ecs \
			--scalable-dimension ecs:service:DesiredCount \
			--resource-id "$resource" \
			>/dev/null
	fi
	
	log "Scaling $service_name down to 0"
	aws ecs update-service \
		--cluster "$CLUSTER_NAME" \
		--service "$service_name" \
		--desired-count 0 \
		>/dev/null

	log "Waiting for $service_name to become stable at 0 tasks..."
	aws ecs wait services-stable \
		--cluster "$CLUSTER_NAME" \
		--services "$service_name"

	log "Deleting service $service_name"
	aws ecs delete-service \
		--cluster "$CLUSTER_NAME" \
		--service "$service_name" \
		--force \
		>/dev/null
	log "Service $service_name deleted"
}

if aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query "clusters[0].status" --output text 2>/dev/null | grep -q ACTIVE
then
	scale_down_and_delete_service my-service-ecs
	scale_down_and_delete_service my-service-ecs-api
else
	log "ECS cluster $CLUSTER_NAME does not exist, skipping service cleanup"
fi

# ---------------------------------------------------------------------------
# 2. ECS cluster
# ---------------------------------------------------------------------------

cluster_status=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query "clusters[0].status" --output text 2>/dev/null || true)
if [[ -n "$cluster_status" && "$cluster_status" == "ACTIVE" ]]
then
	log "Deleting cluster $CLUSTER_NAME"
	aws ecs delete-cluster --cluster "$CLUSTER_NAME" >/dev/null
	log "Cluster $CLUSTER_NAME deleted"
else
	log "Cluster $CLUSTER_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 3. Task definitions: deregister all revisions of both families
# ---------------------------------------------------------------------------

deregister_task_family() {
	local family="$1"
	local arns
	arns=$(aws ecs list-task-definitions --family-prefix "$family" --query "taskDefinitionArns[]" --output text 2>/dev/null || true)

	if [[ -z "$arns" ]]
	then
		log "No task definitions found for family $family"
		return
	fi

	for arn in $arns
	do
		log "Deregistering task definition $arn"
		aws ecs deregister-task-definition --task-definition "$arn" >/dev/null
	done
}

deregister_task_family fargate-task-definition
deregister_task_family fargate-task-definition-api

# ---------------------------------------------------------------------------
# 4. ALB: listener, rules, load balancer, target groups
# ---------------------------------------------------------------------------

if [[ -n "$listener_arn" && "$listener_arn" != "None" ]]
then
	log "Deleting listener (rules are removed with it)"
	aws elbv2 delete-listener --listener-arn "$listener_arn"
else
	log "No listener to delete"
fi

if [[ -n "$lb_arn" && "$lb_arn" != "None" ]]
then
	log "Deleting load balancer, waiting for it to be gone..."
	aws elbv2 delete-load-balancer --load-balancer-arn "$lb_arn"
	aws elbv2 wait load-balancers-deleted --load-balancer-arns "$lb_arn"
	log "Load balancer deleted"
else
	log "No load balancer to delete"
fi

if [[ -n "$target_group_app_arn" && "$target_group_app_arn" != "None" ]]
then
	log "Deleting app target group"
	aws elbv2 delete-target-group --target-group-arn "$target_group_app_arn"
else
	log "No app target group to delete"
fi

if [[ -n "$target_group_api_arn" && "$target_group_api_arn" != "None" ]]
then
	log "Deleting api target group"
	aws elbv2 delete-target-group --target-group-arn "$target_group_api_arn"
else
	log "No api target group to delete"
fi

# ---------------------------------------------------------------------------
# 5. ECR: local images + repositories
# ---------------------------------------------------------------------------

if docker image inspect "$image_app" >/dev/null 2>&1
then
	log "Removing local image $image_app"
	docker rmi -f "$image_app" >/dev/null
else
	log "No local image $image_app to remove"
fi

if docker image inspect "$image_api" >/dev/null 2>&1
then
	log "Removing local image $image_api"
	docker rmi -f "$image_api" >/dev/null
else
	log "No local image $image_api to remove"
fi

if aws ecr describe-repositories --repository-names proj04-app >/dev/null 2>&1
then
	log "Deleting ECR repository proj04-app"
	aws ecr delete-repository --repository-name proj04-app --force >/dev/null
	log "ECR repository proj04-app deleted"
else
	log "ECR repository proj04-app already gone"
fi

if aws ecr describe-repositories --repository-names proj04-api >/dev/null 2>&1
then
	log "Deleting ECR repository proj04-api"
	aws ecr delete-repository --repository-name proj04-api --force >/dev/null
	log "ECR repository proj04-api deleted"
else
	log "ECR repository proj04-api already gone"
fi

# ---------------------------------------------------------------------------
# 6. CloudWatch log groups
# ---------------------------------------------------------------------------

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME_APP" --query "logGroups[0].arn" --output text 2>/dev/null | grep -qv "^None$"
then
	log "Deleting log group $LOG_GROUP_NAME_APP"
	aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME_APP"
else
	log "Log group $LOG_GROUP_NAME_APP already gone"
fi

if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME_API" --query "logGroups[0].arn" --output text 2>/dev/null | grep -qv "^None$"
then
	log "Deleting log group $LOG_GROUP_NAME_API"
	aws logs delete-log-group --log-group-name "$LOG_GROUP_NAME_API"
else
	log "Log group $LOG_GROUP_NAME_API already gone"
fi

# ---------------------------------------------------------------------------
# 7. IAM role
# ---------------------------------------------------------------------------

if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1
then
	log "Detaching $POLICY_ARN from role $ROLE_NAME"
	aws iam detach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN" 2>/dev/null || true
	log "Deleting role $ROLE_NAME"
	aws iam delete-role --role-name "$ROLE_NAME"
	log "Role $ROLE_NAME deleted"
else
	log "Role $ROLE_NAME already gone"
fi

# ---------------------------------------------------------------------------
# 8. Security groups (App before ALB: App references ALB as source)
# ---------------------------------------------------------------------------

if [[ -n "$SG_App_id" && "$SG_App_id" != "None" ]]
then
	log "Deleting SG-App"
	aws ec2 delete-security-group --group-id "$SG_App_id" >/dev/null
else
	log "SG-App already gone"
fi

if [[ -n "$SG_ALB_id" && "$SG_ALB_id" != "None" ]]
then
	log "Deleting SG-ALB"
	aws ec2 delete-security-group --group-id "$SG_ALB_id" >/dev/null
else
	log "SG-ALB already gone"
fi

log "Cleanup complete"
