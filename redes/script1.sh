
REGION="us-east-1"


# Crear una VPC y devolver su ID
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 172.16.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVpc-GateWay}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC creada con ID: $VPC_ID"

# Habilitar DNS en la VPC
aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}"

# Crear subred dentro de la VPC
SUB_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 172.16.0.0/20 \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=MiSubredGateWay}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subred creada con ID: $SUB_ID"

aws ec2 modify-subnet-attribute --subnet-id $SUB_ID --map-public-ip-on-launch

# Crear Security Group
SG_ID=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name gs-Gateway \
  --query GroupId \
  --description "My security group for GateWay" \
  --output text)

echo "Security Group creado con ID: $SG_ID"

# Autorizar el puerto 22 (ssh) para ese SG // esto no le gusta
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Crear EC2 (ejemplo 1)
EC2_ID=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_ID \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2}]' \
    --query 'Instances[0].InstanceId' --output text)

sleep 15

echo "EC2 creada con ID: $EC2_ID"

# ======== 1. Crear IGW ========
IGW_ID=$(aws ec2 create-internet-gateway \
  --region us-east-1 \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# ======== 2. Adjuntar IGW a la VPC ========
echo "Adjuntando Internet Gateway a la VPC..."
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region us-east-1
echo "Internet Gateway adjuntado a la VPC $VPC_ID"

# ======== 3. Crear tabla de enrutamiento ========
RTB_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID\
  --region us-east-1 \
  --query 'RouteTable.RouteTableId' \
  --output text)

# ======== 4. Agregar ruta a Internet ========
echo "Agregando ruta 0.0.0.0/0 hacia el IGW..."
aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION
echo "Ruta agregada correctamente."

# ======== 5. Asociar tabla de enrutamiento a la subred ========
echo "Asociando la tabla de enrutamiento a la subred..."
aws ec2 associate-route-table --subnet-id $SUB_ID --route-table-id $RTB_ID --region $REGION
echo "Tabla de enrutamiento asociada a la subred $SUB_ID"

# ======== FINAL ========
echo "✅ Configuración completada exitosamente"
echo "Detalles:"
echo " - Internet Gateway: $IGW_ID"
echo " - Route Table: $RTB_ID"