#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

asg_name=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my_asg --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || true)
config_policy=$(jq -n \
	'{
		"TargetValue": 50.0,
		"PredefinedMetricSpecification": {
			"PredefinedMetricType": "ASGAverageCPUUtilization"
		}
	}')

policy_arn=$(aws autoscaling describe-policies \
    --auto-scaling-group-name "$asg_name" \
    --policy-names asg-policy-cpu50 \
	--query ScalingPolicies[0].PolicyARN \
	--output text 2>/dev/null || true)
if [[ -z "$policy_arn" || "$policy_arn" == "None" ]]
then
	aws autoscaling put-scaling-policy \
	--policy-name asg-policy-cpu50 \
	--auto-scaling-group-name "$asg_name" \
	--policy-type TargetTrackingScaling \
	--target-tracking-configuration "$config_policy" \
	>/dev/null
	log "ASG Policy created"
else
	log "ASG policy already set"
fi