#!/bin/bash

set -euo pipefail

readonly ROLE_NAME="ecsTaskExecutionRole"
readonly POLICY_ARN="arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
readonly LOG_GROUP_NAME_APP="/ecs/proj04-app"
readonly LOG_GROUP_NAME_API="/ecs/proj04-api"
readonly ENVIRONMENT="dev"
readonly PROJECT="proj04"
readonly port=80

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)
if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	printf "Vpc does not even exist\n"
	exit 1
fi
subnet_pub_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ1" --query "Subnets[0].SubnetId" --output text)
subnet_pub_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ2" --query "Subnets[0].SubnetId" --output text)
subnet_priv_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ1" --query "Subnets[0].SubnetId" --output text)
subnet_priv_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ2" --query "Subnets[0].SubnetId" --output text)

log() {
	printf "==> %s\n" "$1"
}

fail() {
	printf "\033[31mFailed\033[0m: %s\n" "$1" >&2
	exit 1
}

jq_field() {
	local json="$1" filter="$2"
	jq -r "$filter // empty" <<<"$json"
}

aws_id=$(aws sts get-caller-identity --query Account --output text)
ecr_uri_app="$aws_id.dkr.ecr.eu-west-3.amazonaws.com/proj04-app"
ecr_uri_api="$aws_id.dkr.ecr.eu-west-3.amazonaws.com/proj04-api"
image_app="$ecr_uri_app:local"
image_api="$ecr_uri_api:local"
register_id=$(aws ecr describe-repositories \
    --repository-names proj04-app \
    --query 'repositories[0].registryId' \
    --output text 2>/dev/null || echo "None")
if [[ -z "$register_id" || "$register_id" == "None" ]]
then
	log "ECR is getting created"
	register_id=$(aws ecr create-repository \
		--repository-name proj04-app)
	log "ECR repository created"
	aws ecr put-registry-scanning-configuration \
  		--scan-type BASIC \
  		--rules '[{"scanFrequency": "SCAN_ON_PUSH", "repositoryFilters": [{"filter": "*", "filterType": "WILDCARD"}]}]' \
		>/dev/null
else
	log "ECR repository already exist"
fi

register_id=$(aws ecr describe-repositories \
    --repository-names proj04-api \
    --query 'repositories[0].registryId' \
    --output text 2>/dev/null || echo "None")
if [[ -z "$register_id" || "$register_id" == "None" ]]
then
	log "ECR is getting created"
	register_id=$(aws ecr create-repository \
		--repository-name proj04-api)
	log "ECR repository created"
	aws ecr put-registry-scanning-configuration \
  		--scan-type BASIC \
  		--rules '[{"scanFrequency": "SCAN_ON_PUSH", "repositoryFilters": [{"filter": "*", "filterType": "WILDCARD"}]}]' \
		>/dev/null
else
	log "ECR repository already exist"
fi

log "Building the app image"
docker build -t proj04-app:local .
log "Tagging..."
docker tag proj04-app:local "$image_app"
log "Pushing it"
docker push "$image_app"
log "Docker part done successfully"

log "Building the api image"
docker build -f Dockerfile.api -t proj04-api:local .
log "Tagging..."
docker tag proj04-api:local "$image_api"
log "Pushing it"
docker push "$image_api"
log "Docker part done successfully"

if role_arn=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null)
then
	log "Role '$ROLE_NAME' already exists, skipping creation"
else
	role_arn=$(aws iam create-role \
		--role-name "$ROLE_NAME" \
		--assume-role-policy-document "file://templates/policy.json" \
		--tags "[{\"Key\": \"Name\", \"Value\": \"$ROLE_NAME\"}, {\"Key\": \"Project\", \"Value\": \"$PROJECT\"}, {\"Key\": \"Environment\", \"Value\": \"$ENVIRONMENT\"}]" \
		--query "Role.Arn" \
		--output text)
	log "Role '$ROLE_NAME' have been created"
fi

attached_arn=$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" \
	--query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'] | [0].PolicyArn" \
	--output text 2>/dev/null || true)

if [[ "$attached_arn" == "$POLICY_ARN" ]]
then
	log "AmazonECSTaskExecutionRolePolicy is already attached to role '$ROLE_NAME'"
else
	log "Attaching AmazonECSTaskExecutionRolePolicy policy to role '$ROLE_NAME'"
	aws iam attach-role-policy \
		--role-name "$ROLE_NAME" \
		--policy-arn "$POLICY_ARN" \
		>/dev/null
fi

log_arn_app=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME_APP" --query logGroups[0].arn --output text)
if [[ -z "$log_arn_app" || "$log_arn_app" == "None" ]]
then
	log "We create the log group:$LOG_GROUP_NAME_APP"
	aws logs create-log-group --log-group-name "$LOG_GROUP_NAME_APP"
	log "$LOG_GROUP_NAME_APP is created"
else
	log "Log group $LOG_GROUP_NAME_APP already exist"
fi

log_arn_api=$(aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME_API" --query logGroups[0].arn --output text)
if [[ -z "$log_arn_api" || "$log_arn_api" == "None" ]]
then
	log "We create the log group:$LOG_GROUP_NAME_API"
	aws logs create-log-group --log-group-name "$LOG_GROUP_NAME_API"
	log "$LOG_GROUP_NAME_API is created"
else
	log "Log group $LOG_GROUP_NAME_API already exist"
fi

SG_ALB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG ALB" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_ALB_id" || "$SG_ALB_id" == "None" ]]
then
	log "Security Group ALB is created"
	SG_ALB_id=$(aws ec2 create-security-group \
		--group-name SG-ALB \
		--vpc-id "$vpc_id" \
		--description "SG-ALB - public HTTP/HTTPS traffic to ALB"\
		--tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=SG ALB},{Key=Project,Value=proj04},{Key=Environment,Value=dev}]' \
		--query GroupId \
		--output text)
else
	log "SG ALB already exist"
fi
json=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_ALB_id" --output json)
SG_ALB_rules_id=$(jq_field "$json" \
	".SecurityGroupRules[] | select(.IsEgress==false and .FromPort==$port and .ToPort==$port and .CidrIpv4==\"0.0.0.0/0\") | .SecurityGroupRuleId")
if [[ -z "$SG_ALB_rules_id" ]]
then
	log "Creating ALB security group rules"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_ALB_id" \
		--port "$port" \
		--protocol tcp \
		--cidr 0.0.0.0/0 \
		>/dev/null
else
	log "SG ALB rules already exist"
fi

load_balancer_arn=$(aws elbv2 describe-load-balancers --names my-load-balancer --query "LoadBalancers[0].LoadBalancerArn" --output text 2>/dev/null || true)
if [[ -z "$load_balancer_arn" || "$load_balancer_arn" == "None" ]]
then
	log "Create load balancer"
	load_balancer_arn=$(aws elbv2 create-load-balancer \
		--name my-load-balancer \
		--type application \
		--subnets "$subnet_pub_one" "$subnet_pub_two" \
		--security-groups "$SG_ALB_id" \
		--tags Key=Name,Value=my_load_balancer Key=Project,Value=proj04 Key=Environment,Value=dev \
		--query LoadBalancers[0].LoadBalancerArn \
		--output text)
	log "Load balancer created, waiting for it to become active (can take a couple minutes)..."
	aws elbv2 wait load-balancer-available --load-balancer-arns "$load_balancer_arn"
	log "Load balancer is active"
else
	log "Load balancer already exists"
fi

first_target_group_arn=$(aws elbv2 describe-target-groups --names my-ip-tg-one --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
if [[ -z "$first_target_group_arn" || "$first_target_group_arn" == "None" ]]
then
	log "Create first target group"
	first_target_group_arn=$(aws elbv2 create-target-group \
		--name my-ip-tg-one \
		--protocol HTTP \
		--port 8080 \
		--target-type ip \
		--vpc-id "$vpc_id" \
		--health-check-protocol HTTP \
		--health-check-enabled \
		--health-check-path "/health" \
		--tags Key=Name,Value=my-ip-target-group-one Key=Project,Value=proj04 Key=Environment,Value=dev \
		--query TargetGroups[0].TargetGroupArn \
		--output text)
	log "First target group created"
else
	log "First target group already exist"
fi

secnd_target_group_arn=$(aws elbv2 describe-target-groups --names my-ip-tg-two --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
if [[ -z "$secnd_target_group_arn" || "$secnd_target_group_arn" == "None" ]]
then
	log "Create second target group"
	secnd_target_group_arn=$(aws elbv2 create-target-group \
		--name my-ip-tg-two \
		--protocol HTTP \
		--port 8080 \
		--target-type ip \
		--vpc-id "$vpc_id" \
		--health-check-protocol HTTP \
		--health-check-enabled \
		--health-check-path "/" \
		--tags Key=Name,Value=my-ip-target-group-two Key=Project,Value=proj04 Key=Environment,Value=dev \
		--query TargetGroups[0].TargetGroupArn \
		--output text)
	log "Second target group created"
else
	log "Second target group already exist"
fi

listener_arn=$(aws elbv2 describe-listeners --load-balancer-arn "$load_balancer_arn" --query "Listeners[0].ListenerArn" --output text 2>/dev/null || true)
if [[ -z "$listener_arn" || "$listener_arn" == "None" ]]
then
	log "Create listener"
	listener_arn=$(aws elbv2 create-listener \
		--load-balancer-arn "$load_balancer_arn" \
		--protocol HTTP \
		--port 80 \
		--default-actions Type=forward,TargetGroupArn="$first_target_group_arn" \
		--query Listeners[0].ListenerArn \
		--output text)
	aws elbv2 add-tags \
		--resource-arns "$listener_arn" \
		--tags Key=Name,Value=my_listener Key=Project,Value=proj04 Key=Environment,Value=dev \
		>/dev/null
	log "Listener created"
	log "Waiting for propagation"
	sleep 15
else
	log "Listener already exists"
fi

api_rule_arn=$(aws elbv2 describe-rules --listener-arn "$listener_arn" --query "Rules[?Conditions[?Field=='path-pattern' && PathPatternConfig.Values[?@=='/api/*']]].RuleArn" --output text)
if [[ -z "$api_rule_arn" || "$api_rule_arn" == "None" ]]
then
	log "Create listener rules for api"
	api_rule_arn=$(aws elbv2 create-rule \
		--listener-arn "$listener_arn" \
		--priority 10 \
		--conditions '[{"Field":"path-pattern","PathPatternConfig":{"Values":["/api/*"]}}]' \
		--actions Type=forward,TargetGroupArn="$first_target_group_arn" \
		--query Rules[0].RuleArn \
		--output text)
	log "Listener rules created"
else
	log "Rules listener already exist"
fi

app_rule_arn=$(aws elbv2 describe-rules --listener-arn "$listener_arn" --query "Rules[?Conditions[?Field=='path-pattern' && PathPatternConfig.Values[?@=='/*']]].RuleArn" --output text)
if [[ -z "$app_rule_arn" || "$app_rule_arn" == "None" ]]
then
	log "Create listener rules for app"
	app_rule_arn=$(aws elbv2 create-rule \
		--listener-arn "$listener_arn" \
		--priority 20 \
		--conditions '[{"Field":"path-pattern","PathPatternConfig":{"Values":["/*"]}}]' \
		--actions Type=forward,TargetGroupArn="$secnd_target_group_arn" \
		--query Rules[0].RuleArn \
		--output text)
	log "Listener rules created"
else
	log "Rules listener already exist"
fi

jq --arg role "$role_arn" \
	--arg image "$image_app" \
	'.executionRoleArn = $role
	| .containerDefinitions[0].image = $image' \
	templates/task_definition.json > templates/task_definition.json.tmp \
	&& mv templates/task_definition.json.tmp templates/task_definition.json

task_arn_app=$(aws ecs describe-task-definition \
    --task-definition fargate-task-definition \
	--query taskDefinition.taskDefinitionArn \
	--output text 2>/dev/null || true)
if [[ -z "$task_arn_app" || "$task_arn_app" == "None" ]]
then
	log "Registration of app task definition"
	task_arn_app=$(aws ecs register-task-definition \
		--cli-input-json file://templates/task_definition.json \
		--query taskDefinition.taskDefinitionArn \
		--output text)
	log "App task registered"
else
	log "App task definition already registered"
fi

jq --arg role "$role_arn" \
	--arg image "$image_api" \
	'.executionRoleArn = $role
	| .containerDefinitions[0].image = $image' \
	templates/task_definition_api.json > templates/task_definition_api.json.tmp \
	&& mv templates/task_definition_api.json.tmp templates/task_definition_api.json

task_arn_api=$(aws ecs describe-task-definition \
    --task-definition fargate-task-definition-api \
	--query taskDefinition.taskDefinitionArn \
	--output text 2>/dev/null || true)
if [[ -z "$task_arn_api" || "$task_arn_api" == "None" ]]
then
	log "Registration of api task definition"
	task_arn_api=$(aws ecs register-task-definition \
		--cli-input-json file://templates/task_definition_api.json \
		--query taskDefinition.taskDefinitionArn \
		--output text)
	log "Api task registered"
else
	log "Api task definition already registered"
fi

SG_App_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=SG App" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_App_id" || "$SG_App_id" == "None" ]]
then
	log "Security Group App is created"
	SG_App_id=$(aws ec2 create-security-group \
		--group-name SG-App \
		--vpc-id "$vpc_id" \
		--tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=SG App},{Key=Project,Value=proj04},{Key=Environment,Value=dev}]' \
		--description "SG-App - traffic from SG-ALB to application" \
		--query GroupId \
		--output text)
else
	log "SG App already exist"
fi

json_tmp=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$SG_App_id" --output json)
SG_App_rules_id=$(jq_field "$json_tmp" \
	".SecurityGroupRules[] | select(.IsEgress==false and .FromPort==8080 and .ToPort==8080) | .SecurityGroupRuleId")
if [[ -z "$SG_App_rules_id" ]]
then
	log "Create SG App rules"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_App_id" \
		--source-group "$SG_ALB_id" \
		--port 8080 \
		--protocol tcp \
		>/dev/null
else
	log "SG App rules already exist"
fi

cluster_status=$(aws ecs describe-clusters \
	--clusters proj04-cluster \
	--query "clusters[0].status" \
	--output text 2>/dev/null || true)
if [[ -z "$cluster_status" || "$cluster_status" == "None" || "$cluster_status" == "INACTIVE" ]]
then
	log "Create ECS cluster"
	aws ecs create-cluster \
		--cluster-name proj04-cluster \
		--tags key=PROJECT,value=proj04 key=ENVIRONMENT,value=dev \
		--configuration '{"executeCommandConfiguration":{"logging":"DEFAULT"}}' \
		>/dev/null
	log "ECS cluster created"
	sleep 8
else
	log "ECS cluster already exists"
fi

app_service_status=$(aws ecs describe-services \
	--cluster proj04-cluster \
	--services my-service-ecs \
	--query "services[0].status" \
	--output text 2>/dev/null || true)
if [[ -z "$app_service_status" || "$app_service_status" == "None" || "$app_service_status" == "INACTIVE" ]]
then
	log "Create ECS service (app)"
	aws ecs create-service \
		--cluster proj04-cluster \
		--service-name my-service-ecs \
		--task-definition "$task_arn_app" \
		--desired-count 2 \
		--launch-type FARGATE \
		--platform-version LATEST \
		--network-configuration "awsvpcConfiguration={subnets=[$subnet_priv_one,$subnet_priv_two],securityGroups=[$SG_App_id]}" \
		--load-balancers "targetGroupArn=$secnd_target_group_arn,containerName=my-app,containerPort=8080" \
		--tags key=PROJECT,value=proj04 key=ENVIRONMENT,value=dev \
		>/dev/null
	log "ECS service (app) created"
else
	log "ECS service (app) already exists, updating to latest task definition"
	aws ecs update-service \
		--cluster proj04-cluster \
		--service my-service-ecs \
		--task-definition "$task_arn_app" \
		--desired-count 2 \
		>/dev/null
fi

api_service_status=$(aws ecs describe-services \
	--cluster proj04-cluster \
	--services my-service-ecs-api \
	--query "services[0].status" \
	--output text 2>/dev/null || true)
if [[ -z "$api_service_status" || "$api_service_status" == "None" || "$api_service_status" == "INACTIVE" ]]
then
	log "Create ECS service (api)"
	aws ecs create-service \
		--cluster proj04-cluster \
		--service-name my-service-ecs-api \
		--task-definition "$task_arn_api" \
		--desired-count 2 \
		--launch-type FARGATE \
		--platform-version LATEST \
		--network-configuration "awsvpcConfiguration={subnets=[$subnet_priv_one,$subnet_priv_two],securityGroups=[$SG_App_id]}" \
		--load-balancers "targetGroupArn=$first_target_group_arn,containerName=my-api,containerPort=8080" \
		--tags key=PROJECT,value=proj04 key=ENVIRONMENT,value=dev \
		>/dev/null
	log "ECS service (api) created"
else
	log "ECS service (api) already exists, updating to latest task definition"
	aws ecs update-service \
		--cluster proj04-cluster \
		--service my-service-ecs-api \
		--task-definition "$task_arn_api" \
		--desired-count 2 \
		>/dev/null
fi

log "Waiting for services to become stable (can take a couple minutes)..."
aws ecs wait services-stable \
	--cluster proj04-cluster \
	--services my-service-ecs my-service-ecs-api
log "Services are stable"
