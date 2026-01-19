
# Crear una VPC y devolver su ID
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.10.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=MyVpc-GateWay}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC creada con ID: $VPC_ID"

#Creo internet Gateway y lo asocio a la vpc
IGW_ID=$(aws ec2 create-internet-gateway \
 --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# Habilitar DNS en la VPC
aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}"

# Crear subred publica dentro de la VPC
SUB_ID1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 172.16.0.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subred-publica}]' \
  --query 'Subnet.SubnetId' \
  --output text)

  aws ec2 modify-subnet-attribute \
  --subnet-id $SUB_ID1 \
  --map-public-ip-on-launch

echo "Subred publica creada con ID: $SUB_ID1"

#Creo tabla de rutas para la subred publica
RTB_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)

aws ec2 create-route --route-table-id $RTB_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --subnet-id $SUB_ID1 --route-table-id $RTB_ID


# Crear subred privada dentro de la VPC
SUB_ID2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 172.16.1.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=Subred-privada}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subred privada creada con ID: $SUB_ID2"

# Crear Security Group
SG_ID=$(aws ec2 create-security-group \
  --vpc-id $VPC_ID \
  --group-name gs-NatGateway \
  --query GroupId \
  --description "My security group for GateWay" \
  --output text)

# Reglas del grupo de seguridad
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol icmp \
    --port -1 \
    --cidr 0.0.0.0/0


# Crear EC2 en la subred publica
EC2_ID1=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_ID1 \
    --security-group-ids $SG_ID \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-publica}]' \
    --query 'Instances[0].InstanceId' --output text)

echo "ec2 publica creada con ID: $EC2_ID1"  


# Crear EC2 en la subred privada
EC2_ID2=$(aws ec2 run-instances \
    --image-id ami-0360c520857e3138f \
    --region us-east-1 \
    --instance-type t3.micro \
    --key-name vockey \
    --subnet-id $SUB_ID2 \
    --security-group-ids $SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=miEc2-privada}]' \
    --query 'Instances[0].InstanceId' --output text)

  echo "ec2 privada creada con ID: $EC2_ID2"  

#Creo una ip elástica para asociarla al NAT Gateway
EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text)
echo "Elastic IP creada con ID: $EIP_ID"


#Creo el NAT Gateway
NAT_ID=$(aws ec2 create-nat-gateway \
    --subnet-id $SUB_ID1 \
    --allocation-id $EIP_ID \
    --query 'NatGateway.NatGatewayId' \
    --output text)

echo "NAT Gateway creado con ID: $NAT_ID"

aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_ID

#Creo tabla de rutas
RTB_PRIVATE=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text)

echo "Tabla de rutas privada creada con ID: $RTB_PRIVATE"


#Añado la ruta hacia el NAT Gateway
aws ec2 create-route \
    --route-table-id $RTB_PRIVATE \
    --destination-cidr-block 0.0.0.0/0 \
    --nat-gateway-id $NAT_ID


#Asocia la tabla de rutas a la subred privada
aws ec2 associate-route-table \
    --subnet-id $SUB_ID2 \
    --route-table-id $RTB_PRIVATE

echo "Subred privada asociada a tabla de rutas con NAT Gateway"




