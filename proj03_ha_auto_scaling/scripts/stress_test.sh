#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

instance_id=$(aws ec2 describe-instances --filters Name="tag:Project",Values="proj03" Name="instance-state-name",Values="pending,running" --query Reservations[0].Instances[0].InstanceId --output text)

command_id=$(aws ssm send-command \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["stress-ng -c 8 --timeout 180s"]' \
    --targets "Key=instanceids,Values=$instance_id" \
    --query "Command.CommandId" \
    --output text)

log "Stress command sent, waiting for it to finish on the instance (~30s)..."
aws ssm wait command-executed --command-id "$command_id" --instance-id "$instance_id"
log "Stress command finished. CPU spike propagates to CloudWatch with a delay — polling the ASG for scale-out..."

readonly max_attempts=20
readonly poll_interval=30
attempt=1
scaled_out=false
while [[ $attempt -le $max_attempts ]]
do
	instance_count=$(aws autoscaling describe-auto-scaling-groups \
		--auto-scaling-group-names my_asg \
		--query "length(AutoScalingGroups[0].Instances)" \
		--output text)
	log "Attempt $attempt/$max_attempts: $instance_count instance(s) in the ASG"
	if [[ "$instance_count" -gt 2 ]]
	then
		scaled_out=true
		break
	fi
	sleep "$poll_interval"
	attempt=$((attempt + 1))
done

if [[ "$scaled_out" == true ]]
then
	log "Scale-out detected: ASG grew beyond its base capacity"
else
	log "No scale-out detected after $((max_attempts * poll_interval))s — check CloudWatch metrics and the scaling policy"
fi

# log "Instances running from asg:"
# aws ec2 describe-instances --filters Name="Environment",Values="dev" Name="instance-state-name",Values="pending,running" --query Reservations[*].Instances[*].InstanceId --output text
