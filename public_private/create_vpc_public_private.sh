#!/bin/bash

. ./parse_yaml.sh
#sed -e '8,$d' $1 1>/dev/null
eval $(parse_yaml $1 )

#
# Create VPC
#
vpc_id=`aws --profile ${input_cli_profile} ec2 create-vpc --cidr-block ${input_vpc_cidr} | jq -r '.Vpc.VpcId'`
aws --profile ${input_cli_profile} ec2 create-tags --resources ${vpc_id} --tags Key=Name,Value=${input_vpc_name}

#
# Create public subnet
#
public_subnet_id=`aws --profile ${input_cli_profile} ec2 create-subnet --vpc-id ${vpc_id} --cidr-block ${input_public_subnet_cidr} | jq -r '.Subnet.SubnetId'`

#
# Create private subnet
#
private_subnet_id=`aws --profile ${input_cli_profile} ec2 create-subnet --vpc-id ${vpc_id} --cidr-block ${input_private_subnet_cidr} | jq -r '.Subnet.SubnetId'`

#
# Create Internet Gateway
#
igw_id=`aws --profile ${input_cli_profile} ec2 create-internet-gateway | jq -r .InternetGateway.InternetGatewayId`

#
# Attach Internet Gateway to VPC
#
aws --profile ${input_cli_profile} ec2 attach-internet-gateway --internet-gateway-id ${igw_id} --vpc-id ${vpc_id}

#
# Confirm route table
#
public_rtb_id=`aws --profile ${input_cli_profile} ec2 describe-route-tables --filters Name=vpc-id,Values="${vpc_id}" | jq -r '.RouteTables[]|.RouteTableId'`


#
# Create default gateway for public subnet
#
aws --profile ${input_cli_profile} ec2 create-route --route-table-id ${public_rtb_id} --destination-cidr-block 0.0.0.0/0 --gateway-id ${igw_id} 1>/dev/null
aws --profile ${input_cli_profile} ec2 associate-route-table --route-table-id ${public_rtb_id} --subnet-id ${public_subnet_id} 1>/dev/null

#
# get EIP for NAT gateway
#
nat_eip_id=`aws --profile ${input_cli_profile} ec2 allocate-address --domain vpc | jq -r '.AllocationId'`

#
# Create route table for private subnet
#
private_rtb_id=`aws --profile ${input_cli_profile} ec2 create-route-table --vpc-id ${vpc_id} | jq -r '.RouteTable.RouteTableId'`

#
# Create NAT Gateway
#
natgateway_id=`aws --profile ${input_cli_profile} ec2 create-nat-gateway --subnet-id ${public_subnet_id} --allocation-id ${nat_eip_id} | jq -r '.NatGateway.NatGatewayId'`

sleep 30
#
# Attach NAT gateway for public subnet
#
aws --profile ${input_cli_profile} ec2 create-route --route-table-id ${private_rtb_id} --destination-cidr-block 0.0.0.0/0 --nat-gateway-id ${natgateway_id} 1>/dev/null
aws --profile ${input_cli_profile} ec2 associate-route-table --route-table-id ${private_rtb_id} --subnet-id ${private_subnet_id} 1>/dev/null

#
# Create secutiry group for public subnet
#
public_sg_id=`aws --profile ${input_cli_profile} ec2 create-security-group --group-name publicSG --description "publicSG" --vpc-id ${vpc_id} | jq -r '.GroupId'`

#
# Set public SG (only SSH from local NW)
#
aws --profile ${input_cli_profile} ec2 authorize-security-group-ingress --group-id ${public_sg_id} --protocol tcp --port 22 --cidr ${input_local_cidr}

#
# Create security group for private subnet
#
private_sg_id=`aws --profile ${input_cli_profile} ec2 create-security-group --group-name privateSG --description "privateSG" --vpc-id ${vpc_id} | jq -r '.GroupId'`

#
# Set private SG
#
# delete
aws --profile ${input_cli_profile} ec2 revoke-security-group-egress --group-id ${private_sg_id} --protocol all --port all --cidr "0.0.0.0/0"
# ingress
aws --profile ${input_cli_profile} ec2 authorize-security-group-ingress --group-id ${private_sg_id} --protocol tcp --port 22 --source-group ${public_sg_id}
aws --profile ${input_cli_profile} ec2 authorize-security-group-ingress --group-id ${private_sg_id} --protocol tcp --port 22 --source-group ${private_sg_id}
# egress
aws --profile ${input_cli_profile} ec2 authorize-security-group-egress --group-id ${private_sg_id} --protocol tcp --port 80 --cidr "0.0.0.0/0"
aws --profile ${input_cli_profile} ec2 authorize-security-group-egress --group-id ${private_sg_id} --protocol tcp --port 443 --cidr "0.0.0.0/0"

#
# Confirm default NACL
#
private_nacl_association_id=`eval "aws --profile ${input_cli_profile} ec2 describe-network-acls --filters \"Name=vpc-id,Values=${vpc_id}\" | jq -r '.NetworkAcls[].Associations[] | select(.SubnetId==\"${private_subnet_id}\") |.NetworkAclAssociationId'"`
#echo "private subnet NACL association id:${private_nacl_association_id}"

#
# Create Network ACL for private subnet
#
private_nacl_id=`aws --profile ${input_cli_profile} ec2 create-network-acl --vpc-id ${vpc_id} | jq -r '.NetworkAcl.NetworkAclId'`

#
# Create NACL entry for private subnet
#
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --ingress --rule-number 10 --protocol -1 --cidr-block ${input_private_subnet_cidr} --rule-action allow
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --egress --rule-number 10 --protocol -1 --cidr-block ${input_private_subnet_cidr} --rule-action allow
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --ingress --rule-number 20 --protocol -1 --cidr-block ${input_public_subnet_cidr} --rule-action allow
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --egress --rule-number 20 --protocol -1 --cidr-block ${input_public_subnet_cidr} --rule-action allow
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --ingress --rule-number 30 --protocol -1 --cidr-block ${input_vpc_cidr} --rule-action deny
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --egress --rule-number 30 --protocol -1 --cidr-block ${input_vpc_cidr} --rule-action deny
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --ingress --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow
aws --profile ${input_cli_profile} ec2 create-network-acl-entry --network-acl-id ${private_nacl_id} --egress --rule-number 100 --protocol -1 --cidr-block 0.0.0.0/0 --rule-action allow

# Attach new NACL for private subnet
#
private_nacl_association_id=`aws --profile ${input_cli_profile} ec2 replace-network-acl-association --association-id ${private_nacl_association_id} --network-acl-id ${private_nacl_id} | jq -r '.NewAssociationId'`


cp $1 ${1%.*}_out.yaml 
echo "output:">>${1%.*}_out.yaml
echo "  vpc_id: ${vpc_id}">>${1%.*}_out.yaml
echo "  public_subnet_id: ${public_subnet_id}">>${1%.*}_out.yaml
echo "  private_subnet_id: ${private_subnet_id}">>${1%.*}_out.yaml
echo "  internet_gateway_id: ${igw_id}">>${1%.*}_out.yaml
echo "  public_subnet_rtb_id: ${public_rtb_id}">>${1%.*}_out.yaml
echo "  nat_eip_id: ${nat_eip_id}">>${1%.*}_out.yaml
echo "  private_subnet_rtb_id: ${private_rtb_id}">>${1%.*}_out.yaml
echo "  nat_gateway_id: ${natgateway_id}">>${1%.*}_out.yaml
echo "  public_subnet_sg_id: ${public_sg_id}">>${1%.*}_out.yaml
echo "  private_subnet_sg_id: ${private_sg_id}">>${1%.*}_out.yaml
echo "  private_subnet_nacl_id: ${private_nacl_id}">>${1%.*}_out.yaml
echo "  private_subnet_nacl_association_id: ${private_nacl_association_id}">>${1%.*}_out.yaml
