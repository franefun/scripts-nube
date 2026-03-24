#!/bin/bash

Crear una VPC y devolver su ID
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 172.16.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=entorno,Value=prueba}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC creada con ID: $VPC_ID"

# Habilitar DNS en la VPC
aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}"

# Crear subred 1 dentro de la VPC
SUB_ID1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 172.16.16.0/20 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=MiSubredGateWay1}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subred creada 1 con ID: $SUB_ID1"

# Crear subred 2 dentro de la VPC
SUB_ID2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 172.16.0.0/20 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=MiSubredGateWay2}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subred creada 2 con ID: $SUB_ID2"

# Crear EC2
EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_ID1 \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2}]' \
    --query 'Instances[0].InstanceId' --output text)



