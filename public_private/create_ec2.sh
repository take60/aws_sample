#!/bin/bash

. ./parse_yaml.sh
#sed -e '8,$d' $1 1>/dev/null
eval $(parse_yaml $1 ) #1=output_vpc
eval $(parse_yaml $2 ) #2=input_ec2

#
# run instance in public subnet
#
public_instance_id=`aws --profile ${input_cli_profile} ec2 run-instances \
--image-id ${input_ami_id} \
--count 1 \
--instance-type ${input_public_instance_type} \
--key-name ${input_keyname} \
--security-group-ids ${output_public_subnet_sg_id} \
--subnet-id ${output_public_subnet_id} \
--iam-instance-profile Arn=${input_public_iam} \
--block-device-mappings '[{"DeviceName":"/dev/sdb","Ebs":{"DeleteOnTermination":false, "VolumeSize":100,"VolumeType":"gp2","Encrypted":true}}]' \
--private-ip-address ${input_public_private_ip} \
--associate-public-ip-address | jq -c -r '.Instances[]|.InstanceId'`
aws --profile ${input_cli_profile} ec2 create-tags --resources ${public_instance_id} --tags Key=Name,Value=${input_public_instance_name}
#
# get EIP for public ec2
#
ec2_eip_id=`aws --profile ${input_cli_profile} ec2 allocate-address --domain vpc | jq -r '.AllocationId'`

#
# allocate EIP to ec2
#
sleep 100
aws --profile ${input_cli_profile} ec2 associate-address --instance-id ${public_instance_id} --allocation-id ${ec2_eip_id}

#
# run instance in private subnet
#
private_instance_id=`aws --profile ${input_cli_profile} ec2 run-instances \
--image-id ${input_ami_id} \
--count 1 \
--instance-type ${input_private_instance_type} \
--key-name ${input_keyname} \
--security-group-ids ${output_private_subnet_sg_id} \
--subnet-id ${output_private_subnet_id} \
--iam-instance-profile Arn=${input_private_iam} \
--block-device-mappings '[{"DeviceName":"/dev/sdb","Ebs":{"DeleteOnTermination":false, "VolumeSize":100,"VolumeType":"gp2","Encrypted":true}}]' \
--private-ip-address ${input_private_private_ip} | jq -c -r '.Instances[]|.InstanceId'`
aws --profile ${input_cli_profile} ec2 create-tags --resources ${private_instance_id} --tags Key=Name,Value=${input_private_instance_name}


cp $2 ${2%.*}_out.yaml 
echo "output:">>${2%.*}_out.yaml
echo "  private_instance_id: ${private_instance_id}">>${2%.*}_out.yaml
echo "  public_instance_id: ${public_instance_id}">>${2%.*}_out.yaml
