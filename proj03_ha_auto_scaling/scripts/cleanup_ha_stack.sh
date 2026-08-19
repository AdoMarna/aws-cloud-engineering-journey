#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

SG_ALB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG ALB" --query SecurityGroups[0].GroupId --output text 2>/dev/null || true)
SG_App_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG App" --query SecurityGroups[0].GroupId --output text 2>/dev/null || true)
template_id=$(aws ec2 describe-launch-templates --filters "Name=tag:Project,Values=proj03" "Name=tag:Name,Values=my_lt" --query LaunchTemplates[0].LaunchTemplateId --output text 2>/dev/null || true)
target_group_arn=$(aws elbv2 describe-target-groups --names my-tg --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
lb_arn=$(aws elbv2 describe-load-balancers --names my-load-balancer --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)
listener_arn=""
if [[ -n "$lb_arn" && "$lb_arn" != "None" ]]
then
	listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$lb_arn" --query "Listeners[0].ListenerArn" --output text 2>/dev/null || true)
fi
asg_name=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my_asg --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || true)

if [[ -n "$asg_name" && "$asg_name" != "None" ]]
then
	log "Scaling ASG down to 0 and deleting its scaling policy"
	aws autoscaling set-desired-capacity --auto-scaling-group-name my_asg --min-size 0 --desired-capacity 0 2>/dev/null || true
	aws autoscaling delete-policy --auto-scaling-group-name my_asg --policy-name asg-policy-cpu50 2>/dev/null || true

	log "Deleting Auto Scaling Group (force-delete)"
	aws autoscaling delete-auto-scaling-group --auto-scaling-group-name my_asg --force-delete

	log "Waiting for the ASG and its instances to be fully gone (no 'wait' subcommand exists for autoscaling, polling manually)..."
	attempt=1
	readonly max_attempts=40
	readonly poll_interval=15
	while [[ $attempt -le $max_attempts ]]
	do
		remaining_asg=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my_asg --query "AutoScalingGroups[0].AutoScalingGroupName" --output text 2>/dev/null || true)
		remaining_instances=$(aws ec2 describe-instances --filters "Name=tag:Project,Values=proj03" "Name=instance-state-name,Values=pending,running,shutting-down,stopping" --query "Reservations[].Instances[].InstanceId" --output text 2>/dev/null || true)
		log "Attempt $attempt/$max_attempts: asg=$remaining_asg instances=[$remaining_instances]"
		if [[ ( -z "$remaining_asg" || "$remaining_asg" == "None" ) && -z "$remaining_instances" ]]
		then
			log "ASG and instances fully terminated"
			break
		fi
		# Some instances refuse to die on the ASG's own schedule; force them directly.
		if [[ -n "$remaining_instances" ]]
		then
			aws ec2 terminate-instances --instance-ids $remaining_instances >/dev/null 2>&1 || true
		fi
		sleep "$poll_interval"
		attempt=$((attempt + 1))
	done
else
	log "Auto Scaling Group already gone"
fi

if [[ -n "$listener_arn" && "$listener_arn" != "None" ]]
then
	log "Deleting listener"
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

if [[ -n "$target_group_arn" && "$target_group_arn" != "None" ]]
then
	log "Deleting target group"
	aws elbv2 delete-target-group --target-group-arn "$target_group_arn"
else
	log "No target group to delete"
fi

if [[ -n "$template_id" && "$template_id" != "None" ]]
then
	log "Deleting launch template (removes all its versions)"
	aws ec2 delete-launch-template --launch-template-id "$template_id"
else
	log "No launch template to delete"
fi

if [[ -n "$SG_App_id" && "$SG_App_id" != "None" ]]
then
	log "Deleting SG-App"
	aws ec2 delete-security-group --group-id "$SG_App_id"
else
	log "SG-App already gone"
fi
sleep 20
if [[ -n "$SG_ALB_id" && "$SG_ALB_id" != "None" ]]
then
	log "Deleting SG-ALB"
	aws ec2 delete-security-group --group-id "$SG_ALB_id"
else
	log "SG-ALB already gone"
fi

log "Cleanup complete"
