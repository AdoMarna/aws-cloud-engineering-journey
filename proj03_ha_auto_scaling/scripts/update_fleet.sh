#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

lt_id=$(aws ec2 describe-launch-templates --filters "Name=tag:Project,Values=proj03" "Name=tag:Name,Values=my_lt" --query LaunchTemplates[0].LaunchTemplateId --output text)
update_homepage_b64=$(base64 -w0 templates/update_homepage.sh)
launch_template_data=$(jq -n --arg ud "$update_homepage_b64" '{UserData: $ud}')
readonly description="LocalVersion2"
version_nb=$(aws ec2 describe-launch-template-versions \
    --launch-template-id "$lt_id" \
    --versions 2 \
	--query LaunchTemplateVersions[0].VersionNumber \
	--output text)
if [[ -z "$version_nb" || "$version_nb" == 2 ]]
then
	log "Second version already exist"
else
	log "Create an update launch template version"
	aws ec2 create-launch-template-version \
		--launch-template-id "$lt_id" \
		--version-description "$description" \
		--source-version 1 \
		--launch-template-data "$launch_template_data" \
		>/dev/null
	log "New launch template version created"
	log "Refresh of the instances with new version of launch template"
	refresh_id=$(aws autoscaling start-instance-refresh \
		--auto-scaling-group-name my_asg \
		--preferences '{"InstanceWarmup": 120, "MinHealthyPercentage": 100}' \
		--desired-configuration '{"LaunchTemplate": {"LaunchTemplateId": "'$lt_id'", "Version": "2"}}')

	readonly max_attempts=30
	readonly poll_interval=30
	attempt=1
	log "Instant refresh has started, we are now waiting.."
	while [[ $attempt -le $max_attempts ]]
	do
		log "Instance refresh monitoring number :'$attempt'"
		status=$(aws autoscaling describe-instance-refreshes \
		--auto-scaling-group-name my_asg \
		--instance-refresh-ids "$refresh_id" \
		--query InstanceRefreshes[0].Status \
		--output text)
		if [[ "$status" == "Successful" ]]
		then
			log "Instance refresh done"
			break
		fi
		sleep "$poll_interval"
		attempt=$((attempt + 1))
	done
fi