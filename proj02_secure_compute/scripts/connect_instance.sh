#!/bin/bash

set -euo pipefail

instance_1_id=$(aws ec2 describe-instances --filters Name="tag:Name",Values="my_instance_one" Name="instance-state-name",Values="pending,running" --query Reservations[0].Instances[0].InstanceId --output text)
aws ssm start-session --target "$instance_1_id"
