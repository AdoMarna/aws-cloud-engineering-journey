#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

old_instance_id=$(aws ec2 describe-instances --filters Name="tag:Project",Values="proj03" Name="instance-state-name",Values="pending,running" --query "Reservations[0].Instances[0].InstanceId" --output text)
log "Killing instance: $old_instance_id"
aws ec2 terminate-instances --instance-ids "$old_instance_id" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$old_instance_id"
log "Instance $old_instance_id confirmed terminated"

target_group_arn=$(aws elbv2 describe-target-groups --names my-tg --query "TargetGroups[0].TargetGroupArn" --output text)
log "Waiting for the ALB to notice $old_instance_id is gone from the Target Group..."
tg_attempt=1
readonly tg_max_attempts=15
readonly tg_poll_interval=10
while [[ $tg_attempt -le $tg_max_attempts ]]
do
	still_registered=$(aws elbv2 describe-target-health \
		--target-group-arn "$target_group_arn" \
		--query "TargetHealthDescriptions[?Target.Id=='$old_instance_id']" \
		--output text)
	if [[ -z "$still_registered" ]]
	then
		log "$old_instance_id has been deregistered from the Target Group"
		break
	fi
	log "Attempt $tg_attempt/$tg_max_attempts: $old_instance_id still registered ($still_registered)"
	sleep "$tg_poll_interval"
	tg_attempt=$((tg_attempt + 1))
done

log "Target group's health"
aws elbv2 describe-target-health \
    --target-group-arn "$target_group_arn" \
	--query "TargetHealthDescriptions[*].{Id:Target.Id,State:TargetHealth.State}" \
	--output table

log "Waiting for a launch activity newer than the termination..."
kill_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sa_attempt=1
readonly sa_max_attempts=15
readonly sa_poll_interval=10
while [[ $sa_attempt -le $sa_max_attempts ]]
do
	launch_activity=$(aws autoscaling describe-scaling-activities \
		--auto-scaling-group-name my_asg \
		--query "Activities[?StartTime>=\`$kill_time\` && contains(Description, 'Launching')].Description" \
		--output text)
	if [[ -n "$launch_activity" ]]
	then
		log "Launch activity detected: $launch_activity"
		break
	fi
	log "Attempt $sa_attempt/$sa_max_attempts: no launch activity yet"
	sleep "$sa_poll_interval"
	sa_attempt=$((sa_attempt + 1))
done

aws autoscaling describe-scaling-activities --auto-scaling-group-name my_asg --query "Activities[*].Description" --output table

log "Waiting for ASG to relaunch a replacement instance..."

readonly max_attempts=20
readonly poll_interval=30
attempt=1
replaced=false
while [[ $attempt -le $max_attempts ]]
do
	new_instance_ids=$(aws autoscaling describe-auto-scaling-groups \
		--auto-scaling-group-names my_asg \
		--query "AutoScalingGroups[0].Instances[?LifecycleState=='InService'].InstanceId" \
		--output text)
	instance_count=$(wc -w <<<"$new_instance_ids")
	log "Attempt $attempt/$max_attempts: $instance_count instance(s) InService: $new_instance_ids"
	if [[ "$instance_count" -eq 2 && "$new_instance_ids" != *"$old_instance_id"* ]]
	then
		replaced=true
		break
	fi
	sleep "$poll_interval"
	attempt=$((attempt + 1))
done

if [[ "$replaced" == true ]]; then
    log "Self-healing confirmed: $old_instance_id was replaced — current instances: $new_instance_ids"
else
    fail "Self-healing did not complete within $((max_attempts * poll_interval))s"
fi

log "Target group's health"
aws elbv2 describe-target-health \
    --target-group-arn "$target_group_arn" \
	--query "TargetHealthDescriptions[*].{Id:Target.Id,State:TargetHealth.State}" \
	--output table