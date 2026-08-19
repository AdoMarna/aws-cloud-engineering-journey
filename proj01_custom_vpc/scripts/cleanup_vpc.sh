#!/bin/bash

set -euo pipefail

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)

if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	printf "==> The vpc does not exist, nothing to clean up.\n"
	exit 0
fi

# subnets
pub_subnet_id_az1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ1" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
pub_subnet_id_az2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Public-Subnet-AZ2" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
priv_subnet_id_az1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ1" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
priv_subnet_id_az2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Private-Subnet-AZ2" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
iso_subnet_id_az1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Isolated-Subnet-AZ1" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)
iso_subnet_id_az2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=Isolated-Subnet-AZ2" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)

# security groups
SG_ALB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=First Security Group" --query SecurityGroups[0].GroupId --output text)
SG_App_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=Second Security Group" --query SecurityGroups[0].GroupId --output text)
SG_DB_id=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=Third Security Group" --query SecurityGroups[0].GroupId --output text)

# nacl
default_nacl_id=$(aws ec2 describe-network-acls --query "NetworkAcls[?VpcId=='$vpc_id'].NetworkAclId" --output text)
assoc_id_one=$(aws ec2 describe-network-acls --query "NetworkAcls[0].Associations[?SubnetId=='$iso_subnet_id_az1'].NetworkAclAssociationId" --output text)
assoc_id_two=$(aws ec2 describe-network-acls --query "NetworkAcls[0].Associations[?SubnetId=='$iso_subnet_id_az2'].NetworkAclAssociationId" --output text)
nacl_id=$(aws ec2 describe-network-acls --filters "Name=tag:Name,Values=MyNaclCustom" "Name=tag:Project,Values=proj01" --query NetworkAcl.NetworkAclId --output text)

# internet gateway
igw_id=$(aws ec2 describe-internet-gateways --filters "Name=tag:Project,Values=proj01" --query "InternetGateways[0].InternetGatewayId" --output text)

# elastic ips
eip_id_one=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=First EIP" --query "Addresses[0].AllocationId" --output text)
eip_id_two=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=Second EIP" --query "Addresses[0].AllocationId" --output text)

# public route table
pub_route_table_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].RouteTableId" --output text)
pub_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].Associations[?SubnetId=='$pub_subnet_id_az1'].RouteTableAssociationId | [0]" --output text)
pub_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].Associations[?SubnetId=='$pub_subnet_id_az2'].RouteTableAssociationId | [0]" --output text)

# private route tables & NAT gateways
private_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].Associations[?SubnetId=='$priv_subnet_id_az1'].RouteTableAssociationId | [0]" --output text)
private_route_table_id_one=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].RouteTableId" --output text)
nat_id_one=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=First NAT" --query "NatGateways[0].NatGatewayId" --output text)
private_route_table_id_two=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].RouteTableId" --output text)
private_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].Associations[?SubnetId=='$priv_subnet_id_az2'].RouteTableAssociationId | [0]" --output text)
nat_id_two=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Second NAT" --query "NatGateways[0].NatGatewayId" --output text)

# vpc endpoint
vpc_endpoint_id=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=VPC Endpoint" --query VpcEndpoints[0].VpcEndpointId --output text)

# isolated route table
iso_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].Associations[?SubnetId=='$iso_subnet_id_az1'].RouteTableAssociationId | [0]" --output text)
iso_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].Associations[?SubnetId=='$iso_subnet_id_az2'].RouteTableAssociationId | [0]" --output text)
iso_route_table_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].RouteTableId" --output text)

# delete nacl
if [[ -n "$nacl_id" && "$nacl_id" != "None" ]]
then
	printf "==> Reassociating isolated subnets with the default nacl\n"
	if [[ -n "$assoc_id_one" && "$assoc_id_one" != "None" ]]
	then
		aws ec2 replace-network-acl-association --association-id "$assoc_id_one" --network-acl-id "$default_nacl_id" >/dev/null
	fi
	if [[ -n "$assoc_id_two" && "$assoc_id_two" != "None" ]]
	then
		aws ec2 replace-network-acl-association --association-id "$assoc_id_two" --network-acl-id "$default_nacl_id" >/dev/null
	fi

	printf "==> Deleting nacl rules\n"
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 100 >/dev/null
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 100 >/dev/null
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 110 >/dev/null
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 110 >/dev/null
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --ingress --rule-number 120 >/dev/null
	aws ec2 delete-network-acl-entry --network-acl-id "$nacl_id" --egress --rule-number 120 >/dev/null

	printf "==> Deleting the nacl\n"
	aws ec2 delete-network-acl --network-acl-id "$nacl_id" >/dev/null
else
	printf "==> The nacl does not exist (or already deleted), continuing...\n"
fi

# delete sg
# Each rule is revoked individually (not in a single grouped --ip-permissions
# call) because revoke-security-group-ingress is all-or-nothing: if a single
# rule in the batch is already gone, the whole call fails with InvalidPermission.NotFound.
if [[ -n "$SG_DB_id" && "$SG_DB_id" != "None" && -n "$SG_App_id" && "$SG_App_id" != "None" ]]
then
	printf "==> Revoking the SG-DB -> SG-App rule\n"
	aws ec2 revoke-security-group-ingress \
		--group-id "$SG_DB_id" \
		--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 5432, "ToPort": 5432, "UserIdGroupPairs": [{"GroupId": "'"$SG_App_id"'"}]}]' &>/dev/null \
		|| printf "==> SG-DB -> SG-App rule already gone, continuing...\n"
else
	printf "==> SG-DB or SG-App already gone, continuing...\n"
fi

if [[ -n "$SG_App_id" && "$SG_App_id" != "None" && -n "$SG_ALB_id" && "$SG_ALB_id" != "None" ]]
then
	printf "==> Revoking the SG-App -> SG-ALB rule (port 80)\n"
	aws ec2 revoke-security-group-ingress \
		--group-id "$SG_App_id" \
		--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 80, "ToPort": 80, "UserIdGroupPairs": [{"GroupId": "'"$SG_ALB_id"'"}]}]' &>/dev/null \
		|| printf "==> SG-App -> SG-ALB rule (port 80) already gone, continuing...\n"

	printf "==> Revoking the SG-App -> SG-ALB rule (port 443)\n"
	aws ec2 revoke-security-group-ingress \
		--group-id "$SG_App_id" \
		--ip-permissions '[{"IpProtocol": "tcp", "FromPort": 443, "ToPort": 443, "UserIdGroupPairs": [{"GroupId": "'"$SG_ALB_id"'"}]}]' &>/dev/null \
		|| printf "==> SG-App -> SG-ALB rule (port 443) already gone, continuing...\n"
else
	printf "==> SG-App or SG-ALB already gone, continuing...\n"
fi

if [[ -n "$SG_ALB_id" && "$SG_ALB_id" != "None" ]]
then
	printf "==> Revoking the public SG-ALB rule (port 80)\n"
	aws ec2 revoke-security-group-ingress \
		--group-id "$SG_ALB_id" \
		--ip-permissions 'IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges=[{CidrIp=0.0.0.0/0}]' &>/dev/null \
		|| printf "==> Public SG-ALB rule (port 80) already gone, continuing...\n"

	printf "==> Revoking the public SG-ALB rule (port 443)\n"
	aws ec2 revoke-security-group-ingress \
		--group-id "$SG_ALB_id" \
		--ip-permissions 'IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges=[{CidrIp=0.0.0.0/0}]' &>/dev/null \
		|| printf "==> Public SG-ALB rule (port 443) already gone, continuing...\n"
else
	printf "==> SG-ALB already gone, continuing...\n"
fi

if [[ -n "$SG_DB_id" && "$SG_DB_id" != "None" ]]
then
	printf "==> Deleting SG-DB\n"
	aws ec2 delete-security-group --group-id "$SG_DB_id" >/dev/null
else
	printf "==> SG-DB already deleted, continuing...\n"
fi

if [[ -n "$SG_App_id" && "$SG_App_id" != "None" ]]
then
	printf "==> Deleting SG-App\n"
	aws ec2 delete-security-group --group-id "$SG_App_id" >/dev/null
else
	printf "==> SG-App already deleted, continuing...\n"
fi

if [[ -n "$SG_ALB_id" && "$SG_ALB_id" != "None" ]]
then
	printf "==> Deleting SG-ALB\n"
	aws ec2 delete-security-group --group-id "$SG_ALB_id" >/dev/null
else
	printf "==> SG-ALB already deleted, continuing...\n"
fi

# iso route table
if [[ -n "$iso_route_table_id" && "$iso_route_table_id" != "None" ]]
then
	printf "==> Disassociating the isolated route table\n"
	if [[ -n "$iso_az1_associated_id" && "$iso_az1_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$iso_az1_associated_id" >/dev/null
	fi
	if [[ -n "$iso_az2_associated_id" && "$iso_az2_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$iso_az2_associated_id" >/dev/null
	fi

	printf "==> Deleting the isolated route table\n"
	aws ec2 delete-route-table --route-table-id "$iso_route_table_id" >/dev/null
else
	printf "==> Isolated route table already deleted, continuing...\n"
fi

if [[ -n "$vpc_endpoint_id" && "$vpc_endpoint_id" != "None" ]]
then
	printf "==> Deleting the vpc endpoint\n"
	aws ec2 delete-vpc-endpoints --vpc-endpoint-ids "$vpc_endpoint_id" >/dev/null
else
	printf "==> Vpc endpoint already deleted, continuing...\n"
fi

# private route table AZ2
if [[ -n "$nat_id_two" && "$nat_id_two" != "None" ]]
then
	printf "==> Deleting the 2nd NAT\n"
	aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id_two" >/dev/null
	aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat_id_two" >/dev/null
else
	printf "==> 2nd NAT already deleted, continuing...\n"
fi

if [[ -n "$eip_id_two" && "$eip_id_two" != "None" ]]
then
	printf "==> Releasing the 2nd EIP\n"
	aws ec2 release-address --allocation-id "$eip_id_two" >/dev/null
else
	printf "==> 2nd EIP already released, continuing...\n"
fi

if [[ -n "$private_route_table_id_two" && "$private_route_table_id_two" != "None" ]]
then
	printf "==> Deleting the private route AZ2\n"
	aws ec2 delete-route --route-table-id "$private_route_table_id_two" --destination-cidr-block 0.0.0.0/0 2>/dev/null \
		|| printf "==> Private route AZ2 already gone, continuing...\n"

	if [[ -n "$private_az2_associated_id" && "$private_az2_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$private_az2_associated_id" >/dev/null
	fi

	printf "==> Deleting the private route table AZ2\n"
	aws ec2 delete-route-table --route-table-id "$private_route_table_id_two" >/dev/null
else
	printf "==> Private route table AZ2 already deleted, continuing...\n"
fi

# private route table AZ1
if [[ -n "$nat_id_one" && "$nat_id_one" != "None" ]]
then
	printf "==> Deleting the 1st NAT\n"
	aws ec2 delete-nat-gateway --nat-gateway-id "$nat_id_one" >/dev/null
	aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$nat_id_one" >/dev/null
else
	printf "==> 1st NAT already deleted, continuing...\n"
fi

if [[ -n "$eip_id_one" && "$eip_id_one" != "None" ]]
then
	printf "==> Releasing the 1st EIP\n"
	aws ec2 release-address --allocation-id "$eip_id_one" >/dev/null
else
	printf "==> 1st EIP already released, continuing...\n"
fi

if [[ -n "$private_route_table_id_one" && "$private_route_table_id_one" != "None" ]]
then
	printf "==> Deleting the private route AZ1\n"
	aws ec2 delete-route --route-table-id "$private_route_table_id_one" --destination-cidr-block 0.0.0.0/0 2>/dev/null \
		|| printf "==> Private route AZ1 already gone, continuing...\n"

	if [[ -n "$private_az1_associated_id" && "$private_az1_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$private_az1_associated_id" >/dev/null
	fi

	printf "==> Deleting the private route table AZ1\n"
	aws ec2 delete-route-table --route-table-id "$private_route_table_id_one" >/dev/null
else
	printf "==> Private route table AZ1 already deleted, continuing...\n"
fi

# pub route table
if [[ -n "$pub_route_table_id" && "$pub_route_table_id" != "None" ]]
then
	printf "==> Deleting the public route\n"
	aws ec2 delete-route --route-table-id "$pub_route_table_id" --destination-cidr-block 0.0.0.0/0 2>/dev/null \
		|| printf "==> Public route already gone, continuing...\n"

	if [[ -n "$pub_az1_associated_id" && "$pub_az1_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$pub_az1_associated_id" >/dev/null
	fi
	if [[ -n "$pub_az2_associated_id" && "$pub_az2_associated_id" != "None" ]]
	then
		aws ec2 disassociate-route-table --association-id "$pub_az2_associated_id" >/dev/null
	fi

	printf "==> Deleting the public route table\n"
	aws ec2 delete-route-table --route-table-id "$pub_route_table_id" >/dev/null
else
	printf "==> Public route table already deleted, continuing...\n"
fi

if [[ -n "$igw_id" && "$igw_id" != "None" ]]
then
	vpc_id_attached=$(aws ec2 describe-internet-gateways --internet-gateway-id "$igw_id" --query "InternetGateways[0].Attachments[0].VpcId" --output text)
	if [[ "$vpc_id_attached" == "$vpc_id" ]]
	then
		printf "==> Detaching the internet gateway\n"
		aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" >/dev/null
	fi

	printf "==> Deleting the internet gateway\n"
	aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" >/dev/null
else
	printf "==> Internet gateway already deleted, continuing...\n"
fi

# delete subnet
declare -A subnet_ids_to_delete=(
	[Public-Subnet-AZ1]="$pub_subnet_id_az1"
	[Public-Subnet-AZ2]="$pub_subnet_id_az2"
	[Private-Subnet-AZ1]="$priv_subnet_id_az1"
	[Private-Subnet-AZ2]="$priv_subnet_id_az2"
	[Isolated-Subnet-AZ1]="$iso_subnet_id_az1"
	[Isolated-Subnet-AZ2]="$iso_subnet_id_az2"
)

for name in "${!subnet_ids_to_delete[@]}"
do
	id="${subnet_ids_to_delete[$name]}"
	if [[ -n "$id" && "$id" != "None" ]]
	then
		printf "==> Deleting subnet %s\n" "$name"
		aws ec2 delete-subnet --subnet-id "$id" >/dev/null
	else
		printf "==> Subnet %s already deleted, continuing...\n" "$name"
	fi
done

# vpc
printf "==> Deleting the vpc\n"
aws ec2 delete-vpc --vpc-id "$vpc_id"
