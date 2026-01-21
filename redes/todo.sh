
#!/bin/bash

REGION_1="us-east-1"      # Virginia
REGION_2="us-west-2"      # Oregon

echo "========================================="
echo "INICIANDO CREACIÓN DE INFRAESTRUCTURA MULTI-REGIÓN"
echo "========================================="
echo "Región 1: $REGION_1 (Virginia)"
echo "Región 2: $REGION_2 (Oregon)"
echo ""

# ========================================
# REGIÓN 1: US-EAST-1 (VIRGINIA)
# ========================================
echo "========================================="
echo "🇺🇸 CONFIGURANDO REGIÓN 1: VIRGINIA"
echo "========================================="

# CREAR VPC-A EN VIRGINIA
echo "Creando VPC-A en Virginia..."
VPC_A_ID=$(aws ec2 create-vpc \
  --cidr-block 10.10.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-A-Virginia}]' \
  --query 'Vpc.VpcId' \
  --output text --region $REGION_1)

echo "VPC-A creada: $VPC_A_ID"

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_A_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION_1

# CREAR VPC-B EN VIRGINIA
echo "Creando VPC-B en Virginia..."
VPC_B_ID=$(aws ec2 create-vpc \
  --cidr-block 10.20.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-B-Virginia}]' \
  --query 'Vpc.VpcId' \
  --output text --region $REGION_1)

echo "VPC-B creada: $VPC_B_ID"

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_B_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION_1

# INTERNET GATEWAY PARA VPC-A
echo "Creando Internet Gateway para VPC-A..."
IGW_A_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=IGW-A-Virginia}]' \
  --query 'InternetGateway.InternetGatewayId' --output text --region $REGION_1)

aws ec2 attach-internet-gateway --vpc-id $VPC_A_ID --internet-gateway-id $IGW_A_ID --region $REGION_1
echo "IGW-A adjunto"

# SUBREDES EN VPC-A (VIRGINIA)
echo "🔧 Creando subredes en VPC-A..."

SUB_A_PUBLIC_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.10.1.0/24 \
  --availability-zone ${REGION_1}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Public-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_1)

aws ec2 modify-subnet-attribute --subnet-id $SUB_A_PUBLIC_1 --map-public-ip-on-launch --region $REGION_1

SUB_A_PRIVATE_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.10.3.0/24 \
  --availability-zone ${REGION_1}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_1)

SUB_A_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_A_ID \
  --cidr-block 10.10.4.0/24 \
  --availability-zone ${REGION_1}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-A-Private-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_1)

echo "Subredes VPC-A creadas"

# SUBREDES EN VPC-B (VIRGINIA)
echo "🔧 Creando subredes en VPC-B..."

SUB_B_PRIVATE_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_B_ID \
  --cidr-block 10.20.1.0/24 \
  --availability-zone ${REGION_1}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-B-Private-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_1)

SUB_B_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_B_ID \
  --cidr-block 10.20.2.0/24 \
  --availability-zone ${REGION_1}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-B-Private-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_1)

echo "Subredes VPC-B creadas"

# SECURITY GROUPS VIRGINIA
echo "🔒 Creando Security Groups en Virginia..."

SG_A_PUBLIC=$(aws ec2 create-security-group \
  --vpc-id $VPC_A_ID \
  --group-name SG-A-Public-Virginia \
  --description "Public SG for VPC-A Virginia" \
  --query 'GroupId' --output text --region $REGION_1)

aws ec2 authorize-security-group-ingress --group-id $SG_A_PUBLIC --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION_1
aws ec2 authorize-security-group-ingress --group-id $SG_A_PUBLIC --protocol icmp --port -1 --cidr 0.0.0.0/0 --region $REGION_1

SG_A_PRIVATE=$(aws ec2 create-security-group \
  --vpc-id $VPC_A_ID \
  --group-name SG-A-Private-Virginia \
  --description "Private SG for VPC-A Virginia" \
  --query 'GroupId' --output text --region $REGION_1)

aws ec2 authorize-security-group-ingress --group-id $SG_A_PRIVATE --protocol all --cidr 10.0.0.0/8 --region $REGION_1

SG_B_PRIVATE=$(aws ec2 create-security-group \
  --vpc-id $VPC_B_ID \
  --group-name SG-B-Private-Virginia \
  --description "Private SG for VPC-B Virginia" \
  --query 'GroupId' --output text --region $REGION_1)

aws ec2 authorize-security-group-ingress --group-id $SG_B_PRIVATE --protocol all --cidr 10.0.0.0/8 --region $REGION_1

echo "Security Groups creados en Virginia"

# INSTANCIAS EC2 EN VIRGINIA
echo "Creando instancias EC2 en Virginia..."

EC2_A_PUBLIC=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region $REGION_1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_A_PUBLIC_1 \
    --security-group-ids $SG_A_PUBLIC \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Virginia-Public}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 pública Virginia: $EC2_A_PUBLIC"

EC2_A_PRIVATE=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region $REGION_1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_A_PRIVATE_1 \
    --security-group-ids $SG_A_PRIVATE \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Virginia-VPC-A-Private}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 privada VPC-A Virginia: $EC2_A_PRIVATE"

EC2_B_PRIVATE=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region $REGION_1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_B_PRIVATE_1 \
    --security-group-ids $SG_B_PRIVATE \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Virginia-VPC-B-Private}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 privada VPC-B Virginia: $EC2_B_PRIVATE"

# NAT GATEWAY VIRGINIA
echo "Creando NAT Gateway en Virginia..."
EIP_VIRGINIA=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION_1)
NAT_VIRGINIA=$(aws ec2 create-nat-gateway \
  --subnet-id $SUB_A_PUBLIC_1 \
  --allocation-id $EIP_VIRGINIA \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=NAT-Virginia}]' \
  --query 'NatGateway.NatGatewayId' --output text --region $REGION_1)

echo "Esperando NAT Gateway Virginia..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_VIRGINIA --region $REGION_1
echo "NAT Gateway Virginia disponible"

# ========================================
# TRANSIT GATEWAY VIRGINIA
# ========================================
echo ""
echo "Creando Transit Gateway en Virginia..."
TGW_VIRGINIA=$(aws ec2 create-transit-gateway \
  --description "TGW Virginia" \
  --tag-specifications 'ResourceType=transit-gateway,Tags=[{Key=Name,Value=TGW-Virginia}]' \
  --query 'TransitGateway.TransitGatewayId' \
  --output text --region $REGION_1)

echo "TGW Virginia: $TGW_VIRGINIA"
echo "Esperando TGW Virginia..."
sleep 180
echo "TGW Virginia disponible"

# Adjuntar VPC-A al TGW
TGW_ATTACH_VA=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_VIRGINIA \
  --vpc-id $VPC_A_ID \
  --subnet-ids $SUB_A_PRIVATE_1 $SUB_A_PRIVATE_2 \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGW-Attach-VPC-A}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' \
  --output text --region $REGION_1)

echo "VPC-A adjunta a TGW Virginia"

# Adjuntar VPC-B al TGW
TGW_ATTACH_VB=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_VIRGINIA \
  --vpc-id $VPC_B_ID \
  --subnet-ids $SUB_B_PRIVATE_1 $SUB_B_PRIVATE_2 \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGW-Attach-VPC-B}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' \
  --output text --region $REGION_1)

echo "VPC-B adjunta a TGW Virginia"

# ========================================
# REGIÓN 2: US-WEST-2 (OREGON)
# ========================================
echo ""
echo "========================================="
echo "CONFIGURANDO REGIÓN 2: OREGON"
echo "========================================="

# CREAR VPC-C EN OREGON
echo "Creando VPC-C en Oregon..."
VPC_C_ID=$(aws ec2 create-vpc \
  --cidr-block 10.30.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-C-Oregon}]' \
  --query 'Vpc.VpcId' \
  --output text --region $REGION_2)

echo "VPC-C creada: $VPC_C_ID"

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_C_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION_2

# CREAR VPC-D EN OREGON
echo "Creando VPC-D en Oregon..."
VPC_D_ID=$(aws ec2 create-vpc \
  --cidr-block 10.40.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=VPC-D-Oregon}]' \
  --query 'Vpc.VpcId' \
  --output text --region $REGION_2)

echo "VPC-D creada: $VPC_D_ID"

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_D_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region $REGION_2

# INTERNET GATEWAY PARA VPC-C
echo "Creando Internet Gateway para VPC-C..."
IGW_C_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=IGW-C-Oregon}]' \
  --query 'InternetGateway.InternetGatewayId' --output text --region $REGION_2)

aws ec2 attach-internet-gateway --vpc-id $VPC_C_ID --internet-gateway-id $IGW_C_ID --region $REGION_2
echo "IGW-C adjunto"

# SUBREDES EN VPC-C (OREGON)
echo "Creando subredes en VPC-C..."

SUB_C_PUBLIC_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_C_ID \
  --cidr-block 10.30.1.0/24 \
  --availability-zone ${REGION_2}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-C-Public-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_2)

aws ec2 modify-subnet-attribute --subnet-id $SUB_C_PUBLIC_1 --map-public-ip-on-launch --region $REGION_2

SUB_C_PRIVATE_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_C_ID \
  --cidr-block 10.30.3.0/24 \
  --availability-zone ${REGION_2}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-C-Private-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_2)

SUB_C_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_C_ID \
  --cidr-block 10.30.4.0/24 \
  --availability-zone ${REGION_2}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-C-Private-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_2)

echo "Subredes VPC-C creadas"

# SUBREDES EN VPC-D (OREGON)
echo "Creando subredes en VPC-D..."

SUB_D_PRIVATE_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_D_ID \
  --cidr-block 10.40.1.0/24 \
  --availability-zone ${REGION_2}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-D-Private-1}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_2)

SUB_D_PRIVATE_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_D_ID \
  --cidr-block 10.40.2.0/24 \
  --availability-zone ${REGION_2}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=VPC-D-Private-2}]' \
  --query 'Subnet.SubnetId' --output text --region $REGION_2)

echo "Subredes VPC-D creadas"

# SECURITY GROUPS OREGON
echo "Creando Security Groups en Oregon..."

SG_C_PUBLIC=$(aws ec2 create-security-group \
  --vpc-id $VPC_C_ID \
  --group-name SG-C-Public-Oregon \
  --description "Public SG for VPC-C Oregon" \
  --query 'GroupId' --output text --region $REGION_2)

aws ec2 authorize-security-group-ingress --group-id $SG_C_PUBLIC --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION_2
aws ec2 authorize-security-group-ingress --group-id $SG_C_PUBLIC --protocol icmp --port -1 --cidr 0.0.0.0/0 --region $REGION_2

SG_C_PRIVATE=$(aws ec2 create-security-group \
  --vpc-id $VPC_C_ID \
  --group-name SG-C-Private-Oregon \
  --description "Private SG for VPC-C Oregon" \
  --query 'GroupId' --output text --region $REGION_2)

aws ec2 authorize-security-group-ingress --group-id $SG_C_PRIVATE --protocol all --cidr 10.0.0.0/8 --region $REGION_2

SG_D_PRIVATE=$(aws ec2 create-security-group \
  --vpc-id $VPC_D_ID \
  --group-name SG-D-Private-Oregon \
  --description "Private SG for VPC-D Oregon" \
  --query 'GroupId' --output text --region $REGION_2)

aws ec2 authorize-security-group-ingress --group-id $SG_D_PRIVATE --protocol all --cidr 10.0.0.0/8 --region $REGION_2

echo "Security Groups creados en Oregon"


# INSTANCIAS EC2 EN OREGON
echo "Creando instancias EC2 en Oregon..."

EC2_C_PUBLIC=$(aws ec2 run-instances \
    --image-id ami-00f46ccd1cbfb363e \
    --region $REGION_2 \
    --instance-type t3.micro \
    --key-name my-key-pair \
    --subnet-id $SUB_C_PUBLIC_1 \
    --security-group-ids $SG_C_PUBLIC \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Oregon-Public}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 pública Oregon: $EC2_C_PUBLIC"

EC2_C_PRIVATE=$(aws ec2 run-instances \
    --image-id ami-00f46ccd1cbfb363e \
    --region $REGION_2 \
    --instance-type t3.micro \
    --key-name my-key-pair \
    --subnet-id $SUB_C_PRIVATE_1 \
    --security-group-ids $SG_C_PRIVATE \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Oregon-VPC-C-Private}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 privada VPC-C Oregon: $EC2_C_PRIVATE"

EC2_D_PRIVATE=$(aws ec2 run-instances \
    --image-id ami-00f46ccd1cbfb363e \
    --region $REGION_2 \
    --instance-type t3.micro \
    --key-name my-key-pair \
    --subnet-id $SUB_D_PRIVATE_1 \
    --security-group-ids $SG_D_PRIVATE \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=EC2-Oregon-VPC-D-Private}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "EC2 privada VPC-D Oregon: $EC2_D_PRIVATE"

# NAT GATEWAY OREGON
echo "Creando NAT Gateway en Oregon..."
EIP_OREGON=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION_2)
NAT_OREGON=$(aws ec2 create-nat-gateway \
  --subnet-id $SUB_C_PUBLIC_1 \
  --allocation-id $EIP_OREGON \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=NAT-Oregon}]' \
  --query 'NatGateway.NatGatewayId' --output text --region $REGION_2)

echo "Esperando NAT Gateway Oregon..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_OREGON --region $REGION_2
echo "NAT Gateway Oregon disponible"

# ========================================
# TRANSIT GATEWAY OREGON
# ========================================
echo ""
echo "Creando Transit Gateway en Oregon..."
TGW_OREGON=$(aws ec2 create-transit-gateway \
  --description "TGW Oregon" \
  --tag-specifications 'ResourceType=transit-gateway,Tags=[{Key=Name,Value=TGW-Oregon}]' \
  --query 'TransitGateway.TransitGatewayId' \
  --output text --region $REGION_2)

echo "TGW Oregon: $TGW_OREGON"
echo "Esperando TGW Oregon..."
sleep 180
echo "TGW Oregon disponible"

# Adjuntar VPC-C al TGW
TGW_ATTACH_VC=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_OREGON \
  --vpc-id $VPC_C_ID \
  --subnet-ids $SUB_C_PRIVATE_1 $SUB_C_PRIVATE_2 \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGW-Attach-VPC-C}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' \
  --output text --region $REGION_2)

echo "VPC-C adjunta a TGW Oregon"

# Adjuntar VPC-D al TGW
TGW_ATTACH_VD=$(aws ec2 create-transit-gateway-vpc-attachment \
  --transit-gateway-id $TGW_OREGON \
  --vpc-id $VPC_D_ID \
  --subnet-ids $SUB_D_PRIVATE_1 $SUB_D_PRIVATE_2 \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGW-Attach-VPC-D}]' \
  --query 'TransitGatewayVpcAttachment.TransitGatewayAttachmentId' \
  --output text --region $REGION_2)

echo "VPC-D adjunta a TGW Oregon"

# ========================================
# TRANSIT GATEWAY PEERING
# ========================================
echo ""
echo "========================================="
echo "CONFIGURANDO TRANSIT GATEWAY PEERING"
echo "========================================="

# Crear Peering Request desde Virginia a Oregon
TGW_PEERING_ID=$(aws ec2 create-transit-gateway-peering-attachment \
  --transit-gateway-id $TGW_VIRGINIA \
  --peer-account-id '091711377259' \
  --peer-transit-gateway-id $TGW_OREGON \
  --peer-region $REGION_2 \
  --tag-specifications 'ResourceType=transit-gateway-attachment,Tags=[{Key=Name,Value=TGW-Peering-Virginia-Oregon}]' \
  --query 'TransitGatewayPeeringAttachment.TransitGatewayAttachmentId' \
  --output text --region $REGION_1)

echo "TGW Peering Request creado: $TGW_PEERING_ID"
echo "Esperando a que el peering esté pendiente de aceptación..."
sleep 90

# Aceptar el Peering desde Oregon
aws ec2 accept-transit-gateway-peering-attachment \
  --transit-gateway-attachment-id $TGW_PEERING_ID \
  --region $REGION_2 > /dev/null

echo "TGW Peering aceptado"
echo "Esperando a que el peering esté disponible..."
sleep 300

echo "TGW Peering disponible y activo"

# ========================================
# CONFIGURAR RUTAS - VIRGINIA
# ========================================
echo ""
echo "Configurando rutas en Virginia..."

# Tabla pública VPC-A
RTB_A_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id $VPC_A_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-A-Public}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_1)

aws ec2 create-route --route-table-id $RTB_A_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_A_ID --region $REGION_1
aws ec2 associate-route-table --subnet-id $SUB_A_PUBLIC_1 --route-table-id $RTB_A_PUBLIC --region $REGION_1

# Tabla privada VPC-A
RTB_A_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_A_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-A-Private}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_1)

aws ec2 create-route --route-table-id $RTB_A_PRIVATE --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_VIRGINIA --region $REGION_1
aws ec2 create-route --route-table-id $RTB_A_PRIVATE --destination-cidr-block 10.20.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1
aws ec2 create-route --route-table-id $RTB_A_PRIVATE --destination-cidr-block 10.30.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1
aws ec2 create-route --route-table-id $RTB_A_PRIVATE --destination-cidr-block 10.40.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1

aws ec2 associate-route-table --subnet-id $SUB_A_PRIVATE_1 --route-table-id $RTB_A_PRIVATE --region $REGION_1
aws ec2 associate-route-table --subnet-id $SUB_A_PRIVATE_2 --route-table-id $RTB_A_PRIVATE --region $REGION_1

# Tabla privada VPC-B
RTB_B_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_B_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-B-Private}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_1)

aws ec2 create-route --route-table-id $RTB_B_PRIVATE --destination-cidr-block 10.10.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1
aws ec2 create-route --route-table-id $RTB_B_PRIVATE --destination-cidr-block 10.30.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1
aws ec2 create-route --route-table-id $RTB_B_PRIVATE --destination-cidr-block 10.40.0.0/16 --transit-gateway-id $TGW_VIRGINIA --region $REGION_1

aws ec2 associate-route-table --subnet-id $SUB_B_PRIVATE_1 --route-table-id $RTB_B_PRIVATE --region $REGION_1
aws ec2 associate-route-table --subnet-id $SUB_B_PRIVATE_2 --route-table-id $RTB_B_PRIVATE --region $REGION_1

echo "Rutas Virginia configuradas"

# ========================================
# CONFIGURAR RUTAS - OREGON
# ========================================
echo ""
echo "Configurando rutas en Oregon..."

# Tabla pública VPC-C
RTB_C_PUBLIC=$(aws ec2 create-route-table \
  --vpc-id $VPC_C_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-C-Public}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_2)

aws ec2 create-route --route-table-id $RTB_C_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_C_ID --region $REGION_2
aws ec2 associate-route-table --subnet-id $SUB_C_PUBLIC_1 --route-table-id $RTB_C_PUBLIC --region $REGION_2

# Tabla privada VPC-C
RTB_C_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_C_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-C-Private}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_2)

aws ec2 create-route --route-table-id $RTB_C_PRIVATE --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_OREGON --region $REGION_2
aws ec2 create-route --route-table-id $RTB_C_PRIVATE --destination-cidr-block 10.40.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2
aws ec2 create-route --route-table-id $RTB_C_PRIVATE --destination-cidr-block 10.10.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2
aws ec2 create-route --route-table-id $RTB_C_PRIVATE --destination-cidr-block 10.20.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2

aws ec2 associate-route-table --subnet-id $SUB_C_PRIVATE_1 --route-table-id $RTB_C_PRIVATE --region $REGION_2
aws ec2 associate-route-table --subnet-id $SUB_C_PRIVATE_2 --route-table-id $RTB_C_PRIVATE --region $REGION_2

# Tabla privada VPC-D
RTB_D_PRIVATE=$(aws ec2 create-route-table \
  --vpc-id $VPC_D_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=RTB-D-Private}]' \
  --query 'RouteTable.RouteTableId' --output text --region $REGION_2)

aws ec2 create-route --route-table-id $RTB_D_PRIVATE --destination-cidr-block 10.30.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2
aws ec2 create-route --route-table-id $RTB_D_PRIVATE --destination-cidr-block 10.10.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2
aws ec2 create-route --route-table-id $RTB_D_PRIVATE --destination-cidr-block 10.20.0.0/16 --transit-gateway-id $TGW_OREGON --region $REGION_2

aws ec2 associate-route-table --subnet-id $SUB_D_PRIVATE_1 --route-table-id $RTB_D_PRIVATE --region $REGION_2
aws ec2 associate-route-table --subnet-id $SUB_D_PRIVATE_2 --route-table-id $RTB_D_PRIVATE --region $REGION_2

echo "Rutas Oregon configuradas"

# ========================================
# CONFIGURAR RUTAS EN TRANSIT GATEWAYS
# ========================================
echo ""
echo "Configurando rutas estáticas en Transit Gateways..."

# Obtener tabla de rutas del TGW Virginia
TGW_RTB_VIRGINIA=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=$TGW_VIRGINIA" \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text --region $REGION_1)

# Rutas desde Virginia a Oregon (vía peering)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.30.0.0/16 \
  --transit-gateway-route-table-id $TGW_RTB_VIRGINIA \
  --transit-gateway-attachment-id $TGW_PEERING_ID \
  --region $REGION_1

aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.40.0.0/16 \
  --transit-gateway-route-table-id $TGW_RTB_VIRGINIA \
  --transit-gateway-attachment-id $TGW_PEERING_ID \
  --region $REGION_1

echo "Rutas estáticas TGW Virginia -> Oregon configuradas"

# Obtener tabla de rutas del TGW Oregon
TGW_RTB_OREGON=$(aws ec2 describe-transit-gateway-route-tables \
  --filters "Name=transit-gateway-id,Values=$TGW_OREGON" \
  --query 'TransitGatewayRouteTables[0].TransitGatewayRouteTableId' \
  --output text --region $REGION_2)

# Rutas desde Oregon a Virginia (vía peering)
aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.10.0.0/16 \
  --transit-gateway-route-table-id $TGW_RTB_OREGON \
  --transit-gateway-attachment-id $TGW_PEERING_ID \
  --region $REGION_2

aws ec2 create-transit-gateway-route \
  --destination-cidr-block 10.20.0.0/16 \
  --transit-gateway-route-table-id $TGW_RTB_OREGON \
  --transit-gateway-attachment-id $TGW_PEERING_ID \
  --region $REGION_2

echo "Rutas estáticas TGW Oregon -> Virginia configuradas"

# ========================================
# OBTENER IPs PRIVADAS
# ========================================
echo ""
echo "Esperando a que las instancias estén en ejecución..."
sleep 30

echo ""
echo "Obteniendo IPs privadas de las instancias..."

IP_VIRGINIA_A=$(aws ec2 describe-instances \
  --instance-ids $EC2_A_PRIVATE \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region $REGION_1)

IP_VIRGINIA_B=$(aws ec2 describe-instances \
  --instance-ids $EC2_B_PRIVATE \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region $REGION_1)

IP_OREGON_C=$(aws ec2 describe-instances \
  --instance-ids $EC2_C_PRIVATE \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region $REGION_2)

IP_OREGON_D=$(aws ec2 describe-instances \
  --instance-ids $EC2_D_PRIVATE \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text --region $REGION_2)

IP_PUBLIC_VIRGINIA=$(aws ec2 describe-instances \
  --instance-ids $EC2_A_PUBLIC \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text --region $REGION_1)

IP_PUBLIC_OREGON=$(aws ec2 describe-instances \
  --instance-ids $EC2_C_PUBLIC \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text --region $REGION_2)

# ========================================
# RESUMEN FINAL
# ========================================
echo ""
echo "========================================="
echo "INFRAESTRUCTURA MULTI-REGIÓN COMPLETADA"
echo "========================================="
echo ""
echo "ARQUITECTURA GLOBAL:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " VIRGINIA (us-east-1):"
echo "  ├─ VPC-A: $VPC_A_ID (10.10.0.0/16)"
echo "  │  ├─ EC2 Pública: $EC2_A_PUBLIC ($IP_PUBLIC_VIRGINIA)"
echo "  │  └─ EC2 Privada: $EC2_A_PRIVATE ($IP_VIRGINIA_A)"
echo "  ├─ VPC-B: $VPC_B_ID (10.20.0.0/16)"
echo "  │  └─ EC2 Privada: $EC2_B_PRIVATE ($IP_VIRGINIA_B)"
echo "  └─ TGW Virginia: $TGW_VIRGINIA"
echo ""
echo " OREGON (us-west-2):"
echo "  ├─ VPC-C: $VPC_C_ID (10.30.0.0/16)"
echo "  │  ├─ EC2 Pública: $EC2_C_PUBLIC ($IP_PUBLIC_OREGON)"
echo "  │  └─ EC2 Privada: $EC2_C_PRIVATE ($IP_OREGON_C)"
echo "  ├─ VPC-D: $VPC_D_ID (10.40.0.0/16)"
echo "  │  └─ EC2 Privada: $EC2_D_PRIVATE ($IP_OREGON_D)"
echo "  └─ TGW Oregon: $TGW_OREGON"
echo ""
echo " CONECTIVIDAD:"
echo "  ├─ VPC-A ↔ VPC-B: Transit Gateway Virginia"
echo "  ├─ VPC-C ↔ VPC-D: Transit Gateway Oregon"
echo "  └─ Virginia ↔ Oregon: TGW Peering ($TGW_PEERING_ID)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " PRUEBAS DE CONECTIVIDAD:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " CONECTAR A VIRGINIA:"
echo "   ssh -i vockey.pem ec2-user@$IP_PUBLIC_VIRGINIA"
echo ""
echo " PROBAR CONECTIVIDAD LOCAL (Virginia):"
echo "   ssh ec2-user@$IP_VIRGINIA_B"
echo "   ping $IP_VIRGINIA_B"
echo ""
echo " PROBAR CONECTIVIDAD INTER-REGIÓN (Virginia → Oregon):"
echo "   ping $IP_OREGON_C"
echo "   ping $IP_OREGON_D"
echo ""
echo " CONECTAR A OREGON:"
echo "   ssh -i vockey.pem ec2-user@$IP_PUBLIC_OREGON"
echo ""
echo " PROBAR CONECTIVIDAD INVERSA (Oregon → Virginia):"
echo "   ping $IP_VIRGINIA_A"
echo "   ping $IP_VIRGINIA_B"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "¡Listo! Arquitectura multi-región completamente funcional"
echo ""