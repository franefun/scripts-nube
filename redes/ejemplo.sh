
REGION="us-east-1"

# 1️⃣ Crear VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.10.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVpc-GateWay}]' \
  --query 'Vpc.VpcId' \
  --output text --region $REGION)

echo "VPC creada con ID: $VPC_ID"

# Habilitar DNS en la VPC
aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION

# 2️⃣ Crear Internet Gateway y asociarlo
IGW_ID=$(aws ec2 create-internet-gateway \
 --query 'InternetGateway.InternetGatewayId' --output text --region $REGION)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID --region $REGION

# 3️⃣ Crear subredes públicas
SUB_PUBLIC_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.10.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

aws ec2 modify-subnet-attribute --subnet-id $SUB_PUBLIC_1 --map-public-ip-on-launch --region $REGION

SUB_PUBLIC_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.10.2.0/24 \
  --availability-zone ${REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Public-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

aws ec2 modify-subnet-attribute --subnet-id $SUB_PUBLIC_2 --map-public-ip-on-launch --region $REGION

echo "Subredes públicas creadas: $SUB_PUBLIC_1, $SUB_PUBLIC_2"

# 4️⃣ Crear subredes privadas
SUB_PRIVATE_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.10.3.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

SUB_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.10.4.0/24 \
  --availability-zone ${REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Private-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION)

echo "Subredes privadas creadas: $SUB_PRIVATE_1, $SUB_PRIVATE_2"

# 5️⃣ Crear Security Groups
# SG pública: permite SSH y HTTP/HTTPS desde cualquier IP
SG_PUBLIC=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name SG-Public \
  --description "Public SG" \
  --query 'GroupId' --output text --region $REGION)

aws ec2 authorize-security-group-ingress --group-id $SG_PUBLIC --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PUBLIC --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION
aws ec2 authorize-security-group-ingress --group-id $SG_PUBLIC --protocol tcp --port 443 --cidr 0.0.0.0/0 --region $REGION

# SG privada: solo permite acceso desde la SG pública
SG_PRIVATE=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name SG-Private \
  --description "Private SG" \
  --query 'GroupId' --output text --region $REGION)

aws ec2 authorize-security-group-ingress --group-id $SG_PRIVATE --protocol all --source-group $SG_PUBLIC --region $REGION

# Crear EC2 en la subred privada
EC2_ID1=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_PRIVATE_1 \
    --security-group-ids $SG_PRIVATE \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-privada}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "ec2 publica creada con ID: $EC2_ID1"  


# Crear EC2 en la subred publica
EC2_ID2=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_PUBLIC_1 \
    --security-group-ids $SG_PUBLIC \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-publica}]' \
    --query 'Instances[0].InstanceId' --output text)

  echo "ec2 privada creada con ID: $EC2_ID2"  


# 6️⃣ Crear Elastic IP y NAT Gateway en la subred pública 1
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id $SUB_PUBLIC_1 --allocation-id $EIP_ID --query 'NatGateway.NatGatewayId' --output text --region $REGION)
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID --region $REGION

# 7️⃣ Crear tablas de rutas
# Tabla pública 1
RTB_PUBLIC_1=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $RTB_PUBLIC_1 --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUB_PUBLIC_1 --route-table-id $RTB_PUBLIC_1 --region $REGION

# Tabla pública 2
RTB_PUBLIC_2=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $RTB_PUBLIC_2 --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUB_PUBLIC_2 --route-table-id $RTB_PUBLIC_2 --region $REGION

# Tabla privada 1
RTB_PRIVATE_1=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $RTB_PRIVATE_1 --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUB_PRIVATE_1 --route-table-id $RTB_PRIVATE_1 --region $REGION

# Tabla privada 2
RTB_PRIVATE_2=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION)
aws ec2 create-route --route-table-id $RTB_PRIVATE_2 --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_ID --region $REGION
aws ec2 associate-route-table --subnet-id $SUB_PRIVATE_2 --route-table-id $RTB_PRIVATE_2 --region $REGION

# # 8️⃣ Crear NACLs

# 8️⃣ Crear NACLs

# ============================================
# NACL PÚBLICA: Permitir solo SSH, HTTP, HTTPS
# ============================================
NACL_PUBLIC=$(aws ec2 create-network-acl --vpc-id $VPC_ID --query 'NetworkAcl.NetworkAclId' --output text --region $REGION)

# INGRESS (tráfico entrante) - SIN parámetro egress (por defecto es ingress)
# SSH desde cualquier IP
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUBLIC --ingress --rule-number 100 --protocol tcp --port-range From=22,To=22 --rule-action allow --cidr-block 0.0.0.0/0 --region $REGION

# HTTP desde cualquier IP
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUBLIC --ingress --rule-number 110 --protocol tcp --port-range From=80,To=80 --rule-action allow --cidr-block 0.0.0.0/0 --region $REGION

# HTTPS desde cualquier IP
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUBLIC --ingress --rule-number 120 --protocol tcp --port-range From=443,To=443 --rule-action allow --cidr-block 0.0.0.0/0 --region $REGION


# EGRESS (tráfico saliente) - CON parámetro --egress
aws ec2 create-network-acl-entry --network-acl-id $NACL_PUBLIC --egress --rule-number 100 --protocol -1 --rule-action allow --cidr-block 0.0.0.0/0 --region $REGION

# Obtener asociaciones existentes y reemplazarlas
ASSOC_PUB_1=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUB_PUBLIC_1" --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PUBLIC_1'`].NetworkAclAssociationId' --output text --region $REGION)
ASSOC_PUB_2=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUB_PUBLIC_2" --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PUBLIC_2'`].NetworkAclAssociationId' --output text --region $REGION)

aws ec2 replace-network-acl-association --association-id $ASSOC_PUB_1 --network-acl-id $NACL_PUBLIC --region $REGION
aws ec2 replace-network-acl-association --association-id $ASSOC_PUB_2 --network-acl-id $NACL_PUBLIC --region $REGION

# ============================================
# NACL PRIVADA: Denegar tráfico externo entrante
# ============================================
NACL_PRIVATE=$(aws ec2 create-network-acl --vpc-id $VPC_ID --query 'NetworkAcl.NetworkAclId' --output text --region $REGION)

# INGRESS (tráfico entrante) - SIN parámetro egress
# Permitir TODO desde dentro de la VPC (10.10.0.0/16)
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIVATE --ingress --rule-number 100 --protocol -1 --rule-action allow --cidr-block 10.10.0.0/16 --region $REGION

# Denegar todo lo demás desde IPs externas
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIVATE --ingress --rule-number 200 --protocol -1 --rule-action deny --cidr-block 0.0.0.0/0 --region $REGION

# EGRESS (tráfico saliente) - CON parámetro --egress
aws ec2 create-network-acl-entry --network-acl-id $NACL_PRIVATE --egress --rule-number 100 --protocol -1 --rule-action allow --cidr-block 0.0.0.0/0 --region $REGION

# Obtener asociaciones existentes y reemplazarlas
ASSOC_PRIV_1=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUB_PRIVATE_1" --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PRIVATE_1'`].NetworkAclAssociationId' --output text --region $REGION)
ASSOC_PRIV_2=$(aws ec2 describe-network-acls --filters "Name=association.subnet-id,Values=$SUB_PRIVATE_2" --query 'NetworkAcls[0].Associations[?SubnetId==`'$SUB_PRIVATE_2'`].NetworkAclAssociationId' --output text --region $REGION)

aws ec2 replace-network-acl-association --association-id $ASSOC_PRIV_1 --network-acl-id $NACL_PRIVATE --region $REGION
aws ec2 replace-network-acl-association --association-id $ASSOC_PRIV_2 --network-acl-id $NACL_PRIVATE --region $REGION

echo "NACLs configuradas correctamente."
