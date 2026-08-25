#!/bin/bash

set -euo pipefail

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}
aws_id=$(aws sts get-caller-identity --query Account --output text)
ecr_uri_app="$aws_id.dkr.ecr.eu-west-3.amazonaws.com/proj04-app"
image_app="$ecr_uri_app:v2"

log "Building the app image"
docker build -t proj04-app:v2 . >/dev/null
log "Tagging..."
docker tag proj04-app:v2 "$image_app" >/dev/null
log "Pushing it"
docker push "$image_app" >/dev/null
log "Docker part done successfully"

jq --arg image "$image_app" \
	'.containerDefinitions[0].image = $image' \
	templates/task_definition.json > templates/task_definition.json.tmp \
	&& mv templates/task_definition.json.tmp templates/task_definition.json

log "Register updated task definition"
aws ecs register-task-definition \
		--cli-input-json file://templates/task_definition.json \
		>/dev/null

log "Update service with updated task definition"
aws ecs update-service \
    --cluster proj04-cluster \
    --service my-service-ecs \
    --task-definition fargate-task-definition \
	--force-new-deployment \
	>/dev/null