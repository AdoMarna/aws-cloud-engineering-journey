#!/bin/bash

set -euo pipefail

readonly WORKSPACE="${TF_WORKSPACE:-dev}"
readonly VAR_FILE="environments/${WORKSPACE}.tfvars"

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

if [[ ! -f "$VAR_FILE" ]]
then
	fail "Var file $VAR_FILE not found for workspace $WORKSPACE"
fi

log "Checking drift for workspace $WORKSPACE ($VAR_FILE)"

set +e
terraform plan -detailed-exitcode -input=false -var-file="$VAR_FILE" >/tmp/proj05_drift_plan.log 2>&1
exit_code=$?
set -e

case "$exit_code" in
	0)
		log "No drift detected, infrastructure matches the code"
		;;
	2)
		log "Drift detected: real infrastructure differs from the Terraform code"
		cat /tmp/proj05_drift_plan.log
		;;
	*)
		cat /tmp/proj05_drift_plan.log
		fail "terraform plan errored while checking drift"
		;;
esac

rm -f /tmp/proj05_drift_plan.log
exit "$exit_code"
