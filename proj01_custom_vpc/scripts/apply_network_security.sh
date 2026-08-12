#!/bin/bash

set -euo pipefail

vpc_id=$(aws ec2 describe-vpcs --filter "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)

if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	printf "==> The vpc does not exist, run deploy_vpc.sh first.\n" >&2
	exit 1
fi

SG_ALB_id=$(aws ec2 describe-security-groups --filter "Name=tag:Name,Values=First Security Group" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_ALB_id" || "$SG_ALB_id" == "None" ]]
then
	printf "==> Creating SG-ALB\n"
	SG_ALB_id=$(aws ec2 create-security-group --group-name SG-ALB --description "SG-ALB - public HTTP/HTTPS traffic to ALB" --vpc-id "$vpc_id" --tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=First Security Group},{Key=Project,Value=proj01}]' --query GroupId --output text)
else
	printf "==> SG-ALB already created, continuing...\n"
fi

SG_ALB_rules_id=$(aws ec2 describe-security-group-rules --filters Name="group-id",Values="$SG_ALB_id" Name="tag:Name",Values="First Security Group Rules" --query SecurityGroupRules[0].GroupId --output text)
if [[ "$SG_ALB_id" != "$SG_ALB_rules_id" ]]
then
	printf "==> Creating SG-ALB security rules\n"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_ALB_id" \
		--ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' 'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' \
		--tag-specifications ResourceType=security-group-rule,Tags='[{Key=Name,Value=First Security Group Rules},{Key=Project,Value=proj01}]' >/dev/null
else
	printf "==> Rules already in place for SG-ALB, continuing...\n"
fi

SG_App_id=$(aws ec2 describe-security-groups --filter "Name=tag:Name,Values=Second Security Group" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_App_id" || "$SG_App_id" == "None" ]]
then
	printf "==> Creating SG-App\n"
	SG_App_id=$(aws ec2 create-security-group --group-name SG-App --description "SG-App - traffic from SG-ALB to application" --vpc-id "$vpc_id" --tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=Second Security Group},{Key=Project,Value=proj01}]' --query GroupId --output text)
else
	printf "==> SG-App already created, continuing...\n"
fi

SG_App_rules_id=$(aws ec2 describe-security-group-rules --filters Name="group-id",Values="$SG_App_id" Name="tag:Name",Values="Second Security Group Rules" --query SecurityGroupRules[0].GroupId --output text)
if [[ "$SG_App_id" != "$SG_App_rules_id" ]]
then
	printf "==> Creating SG-App security rules\n"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_App_id" \
		--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "UserIdGroupPairs": [{"GroupId": "'"$SG_ALB_id"'"}]}, {"IpProtocol": "tcp", "FromPort": 443, "ToPort": 443, "UserIdGroupPairs": [{"GroupId": "'"$SG_ALB_id"'"}]}]' \
		--tag-specifications ResourceType=security-group-rule,Tags='[{Key=Name,Value=Second Security Group Rules},{Key=Project,Value=proj01}]' >/dev/null
else
	printf "==> Rules already in place for SG-App, continuing...\n"
fi

SG_DB_id=$(aws ec2 describe-security-groups --filter "Name=tag:Name,Values=Third Security Group" --query SecurityGroups[0].GroupId --output text)
if [[ -z "$SG_DB_id" || "$SG_DB_id" == "None" ]]
then
	printf "==> Creating SG-DB\n"
	SG_DB_id=$(aws ec2 create-security-group --group-name SG-DB --description "SG-DB - traffic from SG-App to database" --vpc-id "$vpc_id" --tag-specifications ResourceType=security-group,Tags='[{Key=Name,Value=Third Security Group},{Key=Project,Value=proj01}]' --query GroupId --output text)
else
	printf "==> SG-DB already created, continuing...\n"
fi

SG_DB_rules_id=$(aws ec2 describe-security-group-rules --filters Name="group-id",Values="$SG_DB_id" Name="tag:Name",Values="Third Security Group Rules" --query SecurityGroupRules[0].GroupId --output text)
if [[ "$SG_DB_id" != "$SG_DB_rules_id" ]]
then
	printf "==> Creating SG-DB security rules\n"
	aws ec2 authorize-security-group-ingress \
		--group-id "$SG_DB_id" \
		--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432, "UserIdGroupPairs": [{"GroupId": "'"$SG_App_id"'"}]}]' \
		--tag-specifications ResourceType=security-group-rule,Tags='[{Key=Name,Value=Third Security Group Rules},{Key=Project,Value=proj01}]' >/dev/null
else
	printf "==> Rules already in place for SG-DB, continuing...\n"
fi

iso_sub_id_one=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Isolated-Subnet-AZ1" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
iso_sub_id_two=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Isolated-Subnet-AZ2" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
assoc_id_one=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$vpc_id" --query "NetworkAcls[?Associations[?SubnetId=='$iso_sub_id_one']].Associations[?SubnetId=='$iso_sub_id_one'].NetworkAclAssociationId | [0][0]" --output text)
assoc_id_two=$(aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$vpc_id" --query "NetworkAcls[?Associations[?SubnetId=='$iso_sub_id_two']].Associations[?SubnetId=='$iso_sub_id_two'].NetworkAclAssociationId | [0][0]" --output text)
nacl_id=$(aws ec2 describe-network-acls --filters "Name=tag:Name,Values=MyNaclCustom" "Name=tag:Project,Values=proj01" --query NetworkAcl.NetworkAclId --output text)
if [[ -z "$nacl_id" || "$nacl_id" == "None" ]]
then
	printf "==> Creating the nacl\n"
	nacl_id=$(aws ec2 create-network-acl --vpc-id "$vpc_id" --tag-specifications ResourceType=network-acl,Tags='[{Key=Name,Value=MyNaclCustom},{Key=Project,Value=proj01}]' --query NetworkAcl.NetworkAclId --output text)
	printf "==> Setting up traffic rules\n"
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 100 --protocol -1 --cidr-block 10.0.10.0/24 --rule-action allow >/dev/null
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 100 --protocol -1 --cidr-block 10.0.10.0/24 --rule-action allow >/dev/null
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 110 --protocol -1 --cidr-block 10.0.20.0/24 --rule-action allow >/dev/null
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 110 --protocol -1 --cidr-block 10.0.20.0/24 --rule-action allow >/dev/null
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 120 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action deny >/dev/null
	aws ec2 create-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 120 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action deny >/dev/null
	printf "==> Associating both isolated subnets\n"
	aws ec2 replace-network-acl-association --association-id "$assoc_id_one" --network-acl-id "$nacl_id" >/dev/null
	aws ec2 replace-network-acl-association --association-id "$assoc_id_two" --network-acl-id "$nacl_id" >/dev/null
else
	printf "==> Nacl already in place, continuing...\n"
fi
