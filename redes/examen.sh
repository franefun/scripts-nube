#!/bin/bash

########################################
# 1. Crear VPC
########################################
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.10.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-Examen}]' \
  --query 'Vpc.VpcId' --output text)

echo "VPC creada: $VPC_ID"

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"

########################################
# 2. Internet Gateway
########################################
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "Internet Gateway: $IGW_ID"

########################################
# 3. Crear Subredes (2 Públicas, 2 Privadas)
########################################

# Pública 1
SUB_PUB1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.10.1.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-1}]' \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUB_PUB1 --map-public-ip-on-launch
echo "Subred Pública 1: $SUB_PUB1"

# Pública 2
SUB_PUB2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.10.2.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-2}]' \
  --query 'Subnet.SubnetId' --output text)
aws ec2 modify-subnet-attribute --subnet-id $SUB_PUB2 --map-public-ip-on-launch
echo "Subred Pública 2: $SUB_PUB2"

# Privada 1
SUB_PRIV1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.10.3.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-1}]' \
  --query 'Subnet.SubnetId' --output text)
echo "Subred Privada 1: $SUB_PRIV1"

# Privada 2
SUB_PRIV2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID --cidr-block 10.10.4.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-2}]' \
  --query 'Subnet.SubnetId' --output text)
echo "Subred Privada 2: $SUB_PRIV2"

########################################
# 4. Tablas de rutas públicas
########################################
RTB_PUB1=$(aws ec2 create-route-table --vpc-id $VPC_ID \
          --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUB1 --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $SUB_PUB1 --route-table-id $RTB_PUB1

RTB_PUB2=$(aws ec2 create-route-table --vpc-id $VPC_ID \
          --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PUB2 --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $SUB_PUB2 --route-table-id $RTB_PUB2

########################################
# 5. NAT Gateway (en Public 1)
########################################
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
echo "Elastic IP: $EIP_ID"

NAT_ID=$(aws ec2 create-nat-gateway \
    --subnet-id $SUB_PUB1 \
    --allocation-id $EIP_ID \
    --query 'NatGateway.NatGatewayId' --output text)

echo "Creando NAT..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID
echo "NAT creado: $NAT_ID"

aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

########################################
# 6. Tablas de rutas privadas
########################################
RTB_PRIV1=$(aws ec2 create-route-table --vpc-id $VPC_ID \
            --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIV1 --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
aws ec2 associate-route-table --subnet-id $SUB_PRIV1 --route-table-id $RTB_PRIV1

RTB_PRIV2=$(aws ec2 create-route-table --vpc-id $VPC_ID \
            --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $RTB_PRIV2 --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID
aws ec2 associate-route-table --subnet-id $SUB_PRIV2 --route-table-id $RTB_PRIV2

########################################
# 7. Security Groups (encadenados)
########################################

# SG Público → permite SSH, HTTP, HTTPS
SG_PUB=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name SG-PUBLIC \
  --description "SG Public" \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress --group-id $SG_PUB \
  --protocol tcp --port 22 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PUB \
  --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PUB \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# SG Privado → solo acepta tráfico desde SG Público
SG_PRIV=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name SG-PRIVATE \
  --description "SG Private" \
  --query GroupId --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_PRIV \
  --protocol -1 \
  --source-group $SG_PUB

  # Crear EC2 en la subred publica 1
EC2_ID1=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1a \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $RTB_PUB1 \
    --security-group-ids $SG_PUB \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-publica-1}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "ec2 publica creada con ID: $EC2_ID1"  


# Crear EC2 en la subred privada 1
EC2_ID2=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1a \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_PUB1 \
    --security-group-ids $SG_PRIV \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-privada-1}]' \
    --query 'Instances[0].InstanceId' --output text)

  echo "ec2 privada creada con ID: $EC2_ID2"  

  # Crear EC2 en la subred publica 2
EC2_ID3=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1b \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $RTB_PUB2 \
    --security-group-ids $SG_PUB \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-publica-2}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "ec2 publica creada con ID: $EC2_ID1"  


# Crear EC2 en la subred privada 2
EC2_ID4=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1b \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_PUB2 \
    --security-group-ids $SG_PRIV \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-privada-2}]' \
    --query 'Instances[0].InstanceId' --output text)

  echo "ec2 privada creada con ID: $EC2_ID2"  

########################################
# 8. NACLs (según enunciado)
########################################

# NACL Pública
NACL_PUB=$(aws ec2 create-network-acl \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=NACL-Publica}]' \
  --query 'NetworkAcl.NetworkAclId' \
  --output text)
echo "NACL pública creada: $NACL_PUB"

# Reglas INGRESS públicas
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUB --rule-number 100 --protocol tcp --rule-action allow --ingress --port-range From=22,To=22 --cidr-block 0.0.0.0/0
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUB --rule-number 110 --protocol tcp --rule-action allow --ingress --port-range From=80,To=80 --cidr-block 0.0.0.0/0
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUB --rule-number 120 --protocol tcp --rule-action allow --ingress --port-range From=443,To=443 --cidr-block 0.0.0.0/0

# Reglas EGRESS públicas
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUB --rule-number 100 --protocol -1 --rule-action allow --egress --cidr-block 0.0.0.0/0

# NACL Privada
NACL_PRIV=$(aws ec2 create-network-acl \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=network-acl,Tags=[{Key=Name,Value=NACL-Privada}]' \
  --query 'NetworkAcl.NetworkAclId' \
  --output text)
echo "NACL privada creada: $NACL_PRIV"

# Reglas INGRESS privadas - permitir desde VPC
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIV --rule-number 100 --protocol -1 --rule-action allow --ingress --cidr-block 10.10.0.0/16
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIV --rule-number 110 --protocol -1 --rule-action deny --ingress --cidr-block 0.0.0.0/0

# Reglas EGRESS privadas
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIV --rule-number 100 --protocol -1 --rule-action allow --egress --cidr-block 10.10.0.0/16

# Asociar NACLs
ASSOC_PUB1=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUB_PUB1" \ 
  --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PUB1'`].NetworkAclAssociationId' \
  --output text)

ASSOC_PUB2=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUB_PUB2" \
  --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PUB2'`].NetworkAclAssociationId' \
  --output text)

ASSOC_PRIV1=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUB_PRIV1" \
  --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PRIV1'`].NetworkAclAssociationId' \
  --output text)

ASSOC_PRIV2=$(aws ec2 describe-network-acls \
  --filters "Name=association.subnet-id,Values=$SUB_PRIV2" \
  --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PRIV2'`].NetworkAclAssociationId' \
  --output text)

aws ec2 replace-network-acl-association --association-id $ASSOC_PUB1 --network-acl-id $NACL_PUB
aws ec2 replace-network-acl-association --association-id $ASSOC_PUB2 --network-acl-id $NACL_PUB
aws ec2 replace-network-acl-association --association-id $ASSOC_PRIV1 --network-acl-id $NACL_PRIV
aws ec2 replace-network-acl-association --association-id $ASSOC_PRIV2 --network-acl-id $NACL_PRIV
echo "NACLs asociadas"

########################################
# FIN
########################################
echo "Infraestructura completa desplegada."
