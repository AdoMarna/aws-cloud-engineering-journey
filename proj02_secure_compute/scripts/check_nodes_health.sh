#!/bin/bash

set -euo pipefail

# log <message>: prints a formatted status line.
log() {
	printf "==> %s\n" "$1"
}

# fail <message>: prints an error message to stderr and exits.
fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

my_instance_one_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="my_instance_one" Name="instance-state-name",Values="pending,running,stopping,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)
my_instance_two_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="my_instance_two" Name="instance-state-name",Values="pending,running,stopping,stopped" --query "Reservations[0].Instances[0].InstanceId" --output text)

if [[ -z "$my_instance_one_id" || "$my_instance_one_id" == "None" ]]
then
	fail "Instance 'my_instance_one' introuvable"
fi

if [[ -z "$my_instance_two_id" || "$my_instance_two_id" == "None" ]]
then
	fail "Instance 'my_instance_two' introuvable"
fi

log "Sending health check command to my_instance_one ($my_instance_one_id) and my_instance_two ($my_instance_two_id)"
command_id=$(aws ssm send-command \
	--document-name "AWS-RunShellScript" \
	--parameters commands=["systemctl status nginx"] \
	--instance-ids "$my_instance_one_id" "$my_instance_two_id" \
	--query "Command.CommandId" \
	--output text)

log "Waiting for command execution ($command_id)"
aws ssm wait command-executed \
	--command-id "$command_id" \
	--instance-id "$my_instance_one_id" || true

aws ssm wait command-executed \
	--command-id "$command_id" \
	--instance-id "$my_instance_two_id" || true

report="[]"
for name_id in "my_instance_one:$my_instance_one_id" "my_instance_two:$my_instance_two_id"
do
	name="${name_id%%:*}"
	instance_id="${name_id##*:}"

	invocation=$(aws ssm get-command-invocation \
		--command-id "$command_id" \
		--instance-id "$instance_id" \
		--query "{Status:Status,StandardOutputContent:StandardOutputContent,StandardErrorContent:StandardErrorContent}" \
		--output json)

	node_report=$(jq -n \
		--arg name "$name" \
		--arg instance_id "$instance_id" \
		--argjson invocation "$invocation" \
		'{name: $name, instanceId: $instance_id} + $invocation')

	report=$(jq --argjson node "$node_report" '. + [$node]' <<<"$report")
done

log "Health report (command-id: $command_id)"
jq '.' <<<"$report"
