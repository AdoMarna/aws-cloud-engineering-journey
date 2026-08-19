#!/bin/bash

set -euo pipefail

# Waits for a freshly created resource to become visible via describe (works around
# EC2 API eventual consistency right after a create-*).
wait_until_visible() {
	local description="$1" query_cmd="$2"
	local attempt id
	for attempt in $(seq 1 10)
	do
		id=$(eval "$query_cmd")
		if [[ -n "$id" && "$id" != "None" ]]
		then
			printf "%s\n" "$id"
			return 0
		fi
		printf "==> Waiting for propagation (%s), attempt %s/10...\n" "$description" "$attempt" >&2
		sleep 2
	done
	printf "==> %s still not found after 10 attempts.\n" "$description" >&2
	return 1
}

vpc_id=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text)

if [[ -z "$vpc_id" || "$vpc_id" == "None" ]]
then
	printf "==> Creating the vpc\n"
	aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications ResourceType=vpc,Tags='[{Key=Name,Value=MyVpc},{Key=Project,Value=proj01}]' >/dev/null
	vpc_id=$(wait_until_visible "the vpc" 'aws ec2 describe-vpcs --filters "Name=tag:Project,Values=proj01" --query "Vpcs[0].VpcId" --output text')
else
	printf "==> The vpc already exists, continuing...\n"
fi

# name -> "cidr,az"
declare -A subnets=(
	[Public-Subnet-AZ1]="10.0.1.0/24,eu-west-3a"
	[Public-Subnet-AZ2]="10.0.2.0/24,eu-west-3b"
	[Private-Subnet-AZ1]="10.0.10.0/24,eu-west-3a"
	[Private-Subnet-AZ2]="10.0.20.0/24,eu-west-3b"
	[Isolated-Subnet-AZ1]="10.0.100.0/24,eu-west-3a"
	[Isolated-Subnet-AZ2]="10.0.200.0/24,eu-west-3b"
)

subnet_order=(
	Public-Subnet-AZ1
	Public-Subnet-AZ2
	Private-Subnet-AZ1
	Private-Subnet-AZ2
	Isolated-Subnet-AZ1
	Isolated-Subnet-AZ2
)

declare -A subnet_ids

for name in "${subnet_order[@]}"
do
	cidr="${subnets[$name]%,*}"
	az="${subnets[$name]#*,}"

	subnet_id=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=$name" "Name=vpc-id,Values=$vpc_id" --query "Subnets[0].SubnetId" --output text)

	if [[ -z "$subnet_id" || "$subnet_id" == "None" ]]
	then
		printf "==> Creating subnet %s\n" "$name"
		aws ec2 create-subnet --vpc-id "$vpc_id" --cidr-block "$cidr" --availability-zone "$az" --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$name},{Key=Project,Value=proj01}]" >/dev/null
		subnet_id=$(wait_until_visible "subnet $name" "aws ec2 describe-subnets --filters 'Name=tag:Name,Values=$name' 'Name=vpc-id,Values=$vpc_id' --query 'Subnets[0].SubnetId' --output text")
	else
		printf "==> Subnet %s already exists, continuing...\n" "$name"
	fi

	subnet_ids[$name]="$subnet_id"
done

igw_id=$(aws ec2 describe-internet-gateways --filters "Name=tag:Project,Values=proj01" --query "InternetGateways[0].InternetGatewayId" --output text)

if [[ -z "$igw_id" || "$igw_id" == "None" ]]
then
	printf "==> Creating the internet gateway\n"
	aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=my-igw},{Key=Project,Value=proj01}]' >/dev/null
	igw_id=$(wait_until_visible "the internet gateway" 'aws ec2 describe-internet-gateways --filters "Name=tag:Project,Values=proj01" --query "InternetGateways[0].InternetGatewayId" --output text')
else
	printf "==> The internet gateway already exists, continuing...\n"
fi

vpc_id_attached=$(aws ec2 describe-internet-gateways --internet-gateway-id "$igw_id" --query "InternetGateways[0].Attachments[0].VpcId" --output text)

if [[ "$vpc_id_attached" != "$vpc_id" ]]
then
	printf "==> Attaching the internet gateway to the vpc\n"
	aws ec2 attach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" >/dev/null
else
	printf "==> The internet gateway is already attached to the vpc, continuing...\n"
fi

pub_route_table_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].RouteTableId" --output text)

if [[ -z "$pub_route_table_id" || "$pub_route_table_id" == "None" ]]
then
	printf "==> Creating the public route table\n"
	aws ec2 create-route-table --vpc-id "$vpc_id" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Public Route Table},{Key=Project,Value=proj01}]' >/dev/null
	pub_route_table_id=$(wait_until_visible "the public route table" 'aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].RouteTableId" --output text')
else
	printf "==> The public route table already exists, continuing...\n"
fi

igw_id_in_pub_route=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)

if [[ "$igw_id_in_pub_route" != "$igw_id" ]]
then
	printf "==> Creating the public route"
	aws ec2 create-route --route-table-id "$pub_route_table_id" --destination-cidr-block 0.0.0.0/0 --gateway-id "$igw_id" >/dev/null
else
	printf "==> The public route already exists, continuing...\n"
fi

pub_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Public-Subnet-AZ1]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$pub_az1_associated_id" || "$pub_az1_associated_id" == "None" ]]
then
	printf "==> Associating the route with Public-Subnet-AZ1\n"
	pub_az1_associated_id=$(aws ec2 associate-route-table --route-table-id "$pub_route_table_id"  --subnet-id "${subnet_ids[Public-Subnet-AZ1]}" --query "AssociationId" --output text)
else
	printf "==> Association with Public-Subnet-AZ1 already done, continuing...\n"
fi

pub_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Public Route Table" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Public-Subnet-AZ2]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$pub_az2_associated_id" || "$pub_az2_associated_id" == "None" ]]
then
	printf "==> Associating the route with Public-Subnet-AZ2\n"
	pub_az2_associated_id=$(aws ec2 associate-route-table --route-table-id "$pub_route_table_id"  --subnet-id "${subnet_ids[Public-Subnet-AZ2]}" --query "AssociationId" --output text)
else
	printf "==> Association with Public-Subnet-AZ2 already done, continuing...\n"
fi

eip_id_one=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=First EIP" --query "Addresses[0].AllocationId" --output text)
if [[ -z "$eip_id_one" || "$eip_id_one" == "None" ]]
then
	printf "==> Allocating the 1st EIP\n"
	aws ec2 allocate-address --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=First EIP},{Key=Project,Value=proj01}]' >/dev/null
	eip_id_one=$(wait_until_visible "the 1st EIP" 'aws ec2 describe-addresses --filters "Name=tag:Name,Values=First EIP" --query "Addresses[0].AllocationId" --output text')
else
	printf "==> The 1st EIP has already been allocated, continuing...\n"
fi

nat_id_one=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=First NAT" --query "NatGateways[0].NatGatewayId" --output text)
if [[ -z "$nat_id_one" || "$nat_id_one" == "None" ]]
then
	printf "==> Creating the 1st NAT\n"
	nat_id_one=$(aws ec2 create-nat-gateway --subnet-id "${subnet_ids[Public-Subnet-AZ1]}" --allocation-id "$eip_id_one" --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=First NAT},{Key=Project,Value=proj01}]' --query NatGateway.NatGatewayId --output text)
	wait_until_visible "the 1st NAT" 'aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=First NAT" --query "NatGateways[0].NatGatewayId" --output text' >/dev/null
	aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_id_one" >/dev/null
else
	printf "==> The 1st NAT already exists, continuing...\n"
fi

private_route_table_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].RouteTableId" --output text)

if [[ -z "$private_route_table_id" || "$private_route_table_id" == "None" ]]
then
	printf "==> Creating the private route table\n"
	aws ec2 create-route-table --vpc-id "$vpc_id" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private-RT-AZ1},{Key=Project,Value=proj01}]' >/dev/null
	private_route_table_id=$(wait_until_visible "the private route table AZ1" 'aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].RouteTableId" --output text')
else
	printf "==> The private route table already exists, continuing...\n"
fi

nat_id_in_priv_route_az1=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text)
if [[ "$nat_id_in_priv_route_az1" != "$nat_id_one" ]]
then
	printf "==> Creating the private route"
	aws ec2 create-route --route-table-id "$private_route_table_id" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_id_one" >/dev/null
else
	printf "==> The private route already exists, continuing...\n"
fi

private_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ1" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Private-Subnet-AZ1]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$private_az1_associated_id" || "$private_az1_associated_id" == "None" ]]
then
	printf "==> Associating the route with Private-Subnet-AZ1\n"
	private_az1_associated_id=$(aws ec2 associate-route-table --route-table-id "$private_route_table_id"  --subnet-id "${subnet_ids[Private-Subnet-AZ1]}" --query "AssociationId" --output text)
else
	printf "==> Association with Private-Subnet-AZ1 already done, continuing...\n"
fi

eip_id_two=$(aws ec2 describe-addresses --filters "Name=tag:Name,Values=Second EIP" --query "Addresses[0].AllocationId" --output text)
if [[ -z "$eip_id_two" || "$eip_id_two" == "None" ]]
then
	printf "==> Allocating the 2nd EIP\n"
	aws ec2 allocate-address --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=Second EIP},{Key=Project,Value=proj01}]' >/dev/null
	eip_id_two=$(wait_until_visible "the 2nd EIP" 'aws ec2 describe-addresses --filters "Name=tag:Name,Values=Second EIP" --query "Addresses[0].AllocationId" --output text')
else
	printf "==> The 2nd EIP has already been allocated, continuing...\n"
fi

nat_id_two=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Second NAT" --query "NatGateways[0].NatGatewayId" --output text)
if [[ -z "$nat_id_two" || "$nat_id_two" == "None" ]]
then
	printf "==> Creating the 2nd NAT\n"
	nat_id_two=$(aws ec2 create-nat-gateway --subnet-id "${subnet_ids[Public-Subnet-AZ2]}" --allocation-id "$eip_id_two" --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=Second NAT},{Key=Project,Value=proj01}]' --query NatGateway.NatGatewayId --output text)
	wait_until_visible "the 2nd NAT" 'aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=Second NAT" --query "NatGateways[0].NatGatewayId" --output text' >/dev/null
	aws ec2 wait nat-gateway-available --nat-gateway-ids "$nat_id_two" >/dev/null
else
	printf "==> The 2nd NAT already exists, continuing...\n"
fi

private_route_table_id_two=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].RouteTableId" --output text)

if [[ -z "$private_route_table_id_two" || "$private_route_table_id_two" == "None" ]]
then
	printf "==> Creating the private route table 2\n"
	aws ec2 create-route-table --vpc-id "$vpc_id" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Private-RT-AZ2},{Key=Project,Value=proj01}]' >/dev/null
	private_route_table_id_two=$(wait_until_visible "the private route table AZ2" 'aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].RouteTableId" --output text')
else
	printf "==> The private route table 2 already exists, continuing...\n"
fi

nat_id_in_priv_route_az2=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text)
if [[ "$nat_id_in_priv_route_az2" != "$nat_id_two" ]]
then
	printf "==> Creating the private route"
	aws ec2 create-route --route-table-id "$private_route_table_id_two" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$nat_id_two" >/dev/null
else
	printf "==> The private route already exists, continuing...\n"
fi

private_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Private-RT-AZ2" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Private-Subnet-AZ2]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$private_az2_associated_id" || "$private_az2_associated_id" == "None" ]]
then
	printf "==> Associating the route with Private-Subnet-AZ2\n"
	private_az2_associated_id=$(aws ec2 associate-route-table --route-table-id "$private_route_table_id_two"  --subnet-id "${subnet_ids[Private-Subnet-AZ2]}" --query "AssociationId" --output text)
else
	printf "==> Association with Private-Subnet-AZ2 already done, continuing...\n"
fi

iso_route_table_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].RouteTableId" --output text)

if [[ -z "$iso_route_table_id" || "$iso_route_table_id" == "None" ]]
then
	printf "==> Creating the isolated route table\n"
	aws ec2 create-route-table --vpc-id "$vpc_id" --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=Isolated Route Table},{Key=Project,Value=proj01}]' >/dev/null
	iso_route_table_id=$(wait_until_visible "the isolated route table" 'aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].RouteTableId" --output text')
else
	printf "==> The isolated route table already exists, continuing...\n"
fi

iso_az1_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Isolated-Subnet-AZ1]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$iso_az1_associated_id" || "$iso_az1_associated_id" == "None" ]]
then
	printf "==> Associating the route with Isolated-Subnet-AZ1\n"
	iso_az1_associated_id=$(aws ec2 associate-route-table --route-table-id "$iso_route_table_id"  --subnet-id "${subnet_ids[Isolated-Subnet-AZ1]}" --query "AssociationId" --output text)
else
	printf "==> Association with Isolated-Subnet-AZ1 already done, continuing...\n"
fi

iso_az2_associated_id=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=Isolated Route Table" --query "RouteTables[0].Associations[?SubnetId=='${subnet_ids[Isolated-Subnet-AZ2]}'].RouteTableAssociationId | [0]" --output text)
if [[ -z "$iso_az2_associated_id" || "$iso_az2_associated_id" == "None" ]]
then
	printf "==> Associating the route with Isolated-Subnet-AZ2\n"
	iso_az2_associated_id=$(aws ec2 associate-route-table --route-table-id "$iso_route_table_id"  --subnet-id "${subnet_ids[Isolated-Subnet-AZ2]}" --query "AssociationId" --output text)
else
	printf "==> Association with Isolated-Subnet-AZ2 already done, continuing...\n"
fi

# bash scripts/apply_network_security.sh

vpc_endpoint_id=$(aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=VPC Endpoint" --query VpcEndpoints[0].VpcEndpointId --output text)
if [[ -z "$vpc_endpoint_id" || "$vpc_endpoint_id" == "None" ]]
then
	printf "==> Creating the vpc endpoint\n"
	aws ec2 create-vpc-endpoint --vpc-id "$vpc_id" --service-name com.amazonaws.eu-west-3.s3 --route-table-ids "$private_route_table_id" "$private_route_table_id_two" --tag-specifications 'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=VPC Endpoint},{Key=Project,Value=proj01}]' >/dev/null
	vpc_endpoint_id=$(wait_until_visible "the vpc endpoint" 'aws ec2 describe-vpc-endpoints --filters "Name=tag:Name,Values=VPC Endpoint" --query "VpcEndpoints[0].VpcEndpointId" --output text')
else
	printf "==> The vpc endpoint already exists, continuing..."
fi
