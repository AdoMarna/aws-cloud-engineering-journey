#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

first_target_scalable_arn=$(aws application-autoscaling describe-scalable-targets \
    --service-namespace ecs \
	--resource-id service/proj04-cluster/my-service-ecs \
	--query ScalableTargets[0].ScalableTargetARN \
	--output text 2>/dev/null || true)
if [[ -z "$first_target_scalable_arn" || "$first_target_scalable_arn" == "None" ]]
then
	log "Register scalable target"
	aws application-autoscaling register-scalable-target \
		--service-namespace ecs \
		--scalable-dimension ecs:service:DesiredCount \
		--resource-id service/proj04-cluster/my-service-ecs \
		--min-capacity 2 --max-capacity 6 \
		--tags Project=proj04,Environment=dev \
		>/dev/null
	log "Done"
else
	log "Scalable target already registered"
fi

scnd_target_scalable_arn=$(aws application-autoscaling describe-scalable-targets \
    --service-namespace ecs \
	--resource-id service/proj04-cluster/my-service-ecs-api \
	--query ScalableTargets[0].ScalableTargetARN \
	--output text 2>/dev/null || true)
if [[ -z "$scnd_target_scalable_arn" || "$scnd_target_scalable_arn" == "None" ]]
then
	log "Register scalable target"
	aws application-autoscaling register-scalable-target \
		--service-namespace ecs \
		--scalable-dimension ecs:service:DesiredCount \
		--resource-id service/proj04-cluster/my-service-ecs-api \
		--min-capacity 2 --max-capacity 6 \
		--tags Project=proj04,Environment=dev \
		>/dev/null
	log "Done"
else
	log "Scalable target already registered"
fi

config_file=$(jq -n \
'{
     "TargetValue": 60.0,
     "PredefinedMetricSpecification": {
         "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
     }
}')

app_policy_check=$(aws application-autoscaling describe-scaling-policies \
	--service-namespace ecs \
	--resource-id service/proj04-cluster/my-service-ecs \
	--query ScalingPolicies[0].PolicyName \
	--output text)
if [[ -z "$app_policy_check" || "$app_policy_check" == "None" ]]
then
	log "Set autoscaling policy"
	aws application-autoscaling put-scaling-policy \
	--service-namespace ecs \
	--scalable-dimension ecs:service:DesiredCount \
	--resource-id service/proj04-cluster/my-service-ecs \
	--policy-name cpu60-target-tracking-scaling-policy --policy-type TargetTrackingScaling \
	--target-tracking-scaling-policy-configuration "$config_file" \
	>/dev/null
	log "Done"
else
	log "Autoscalling policy already set"
fi

api_policy_check=$(aws application-autoscaling describe-scaling-policies \
	--service-namespace ecs \
	--resource-id service/proj04-cluster/my-service-ecs-api \
	--query ScalingPolicies[0].PolicyName \
	--output text)
if [[ -z "$api_policy_check" || "$api_policy_check" == "None" ]]
then
	log "Set autoscaling policy"
	aws application-autoscaling put-scaling-policy \
	--service-namespace ecs \
	--scalable-dimension ecs:service:DesiredCount \
	--resource-id service/proj04-cluster/my-service-ecs-api \
	--policy-name cpu60-target-tracking-scaling-policy --policy-type TargetTrackingScaling \
	--target-tracking-scaling-policy-configuration "$config_file" \
	>/dev/null
	log "Done"
else
	log "Autoscalling policy already set"
fi