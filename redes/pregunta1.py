#!/usr/bin/env python3

import boto3
import time

# Configuración
REGION = "us-east-1"
VPC_CIDR = "15.0.0.0/20"
SUBNET_PUBLIC_CIDR = "15.0.1.0/24"      # Frontend (accesible desde internet)
SUBNET_PRIVATE_1_CIDR = "15.0.2.0/24"   # Backend (privada)
SUBNET_PRIVATE_2_CIDR = "15.0.3.0/24"   # Base de datos (privada)

print("=" * 60)
print("CREANDO APLICACION WEB DE 3 CAPAS")
print("=" * 60)
print(f"Region: {REGION}a")
print(f"VPC CIDR: {VPC_CIDR}")
print()

# Cliente EC2
ec2 = boto3.client('ec2', region_name=REGION)

# ========================================
# 1. CREAR VPC
# ========================================
print("Creando VPC...")
vpc_response = ec2.create_vpc(
    CidrBlock=VPC_CIDR,
    TagSpecifications=[{
        'ResourceType': 'vpc',
        'Tags': [{'Key': 'Name', 'Value': 'VPC-3Tier-App'}]
    }]
)
VPC_ID = vpc_response['Vpc']['VpcId']
print(f"VPC creada: {VPC_ID}")

# Habilitar DNS
ec2.modify_vpc_attribute(VpcId=VPC_ID, EnableDnsHostnames={'Value': True})
ec2.modify_vpc_attribute(VpcId=VPC_ID, EnableDnsSupport={'Value': True})

# ========================================
# 2. CREAR INTERNET GATEWAY
# ========================================
print("\nCreando Internet Gateway...")
igw_response = ec2.create_internet_gateway(
    TagSpecifications=[{
        'ResourceType': 'internet-gateway',
        'Tags': [{'Key': 'Name', 'Value': 'IGW-3Tier'}]
    }]
)
IGW_ID = igw_response['InternetGateway']['InternetGatewayId']

ec2.attach_internet_gateway(VpcId=VPC_ID, InternetGatewayId=IGW_ID)
print(f"Internet Gateway adjunto: {IGW_ID}")

# ========================================
# 3. CREAR SUBREDES
# ========================================
print("\nCreando subredes...")

# Subred pública (Frontend)
subnet_public_response = ec2.create_subnet(
    VpcId=VPC_ID,
    CidrBlock=SUBNET_PUBLIC_CIDR,
    AvailabilityZone=f'{REGION}a',
    TagSpecifications=[{
        'ResourceType': 'subnet',
        'Tags': [{'Key': 'Name', 'Value': 'Subnet-Public-Frontend'}]
    }]
)
SUBNET_PUBLIC = subnet_public_response['Subnet']['SubnetId']
ec2.modify_subnet_attribute(SubnetId=SUBNET_PUBLIC, MapPublicIpOnLaunch={'Value': True})
print(f"Subred publica (Frontend): {SUBNET_PUBLIC}")

# Subred privada 1 (Backend)
subnet_private_1_response = ec2.create_subnet(
    VpcId=VPC_ID,
    CidrBlock=SUBNET_PRIVATE_1_CIDR,
    AvailabilityZone=f'{REGION}a',
    TagSpecifications=[{
        'ResourceType': 'subnet',
        'Tags': [{'Key': 'Name', 'Value': 'Subnet-Private-Backend'}]
    }]
)
SUBNET_PRIVATE_1 = subnet_private_1_response['Subnet']['SubnetId']
print(f"Subred privada (Backend): {SUBNET_PRIVATE_1}")

# Subred privada 2 (Base de datos)
subnet_private_2_response = ec2.create_subnet(
    VpcId=VPC_ID,
    CidrBlock=SUBNET_PRIVATE_2_CIDR,
    AvailabilityZone=f'{REGION}a',
    TagSpecifications=[{
        'ResourceType': 'subnet',
        'Tags': [{'Key': 'Name', 'Value': 'Subnet-Private-Database'}]
    }]
)
SUBNET_PRIVATE_2 = subnet_private_2_response['Subnet']['SubnetId']
print(f"Subred privada (Database): {SUBNET_PRIVATE_2}")

# ========================================
# 4. CREAR NAT GATEWAY
# ========================================
print("\nCreando NAT Gateway para acceso a internet desde subredes privadas...")

# Asignar Elastic IP
eip_response = ec2.allocate_address(Domain='vpc')
EIP_ID = eip_response['AllocationId']

# Crear NAT Gateway en subred pública
nat_response = ec2.create_nat_gateway(
    SubnetId=SUBNET_PUBLIC,
    AllocationId=EIP_ID,
    TagSpecifications=[{
        'ResourceType': 'natgateway',
        'Tags': [{'Key': 'Name', 'Value': 'NAT-3Tier'}]
    }]
)
NAT_ID = nat_response['NatGateway']['NatGatewayId']

print(f"Esperando NAT Gateway disponible...")
waiter = ec2.get_waiter('nat_gateway_available')
waiter.wait(NatGatewayIds=[NAT_ID])
print(f"NAT Gateway disponible: {NAT_ID}")

# ========================================
# 5. CREAR SECURITY GROUPS
# ========================================
print("\nCreando Security Groups...")

# SG Frontend (accesible desde internet: HTTP, HTTPS, SSH)
sg_frontend_response = ec2.create_security_group(
    VpcId=VPC_ID,
    GroupName='SG-Frontend',
    Description='Security Group for Frontend (public access)'
)
SG_FRONTEND = sg_frontend_response['GroupId']

ec2.authorize_security_group_ingress(
    GroupId=SG_FRONTEND,
    IpPermissions=[
        {'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
        {'IpProtocol': 'tcp', 'FromPort': 80, 'ToPort': 80, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
        {'IpProtocol': 'tcp', 'FromPort': 443, 'ToPort': 443, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
    ]
)
print(f"SG Frontend: {SG_FRONTEND} (SSH, HTTP, HTTPS desde internet)")

# SG Backend (solo accesible desde Frontend)
sg_backend_response = ec2.create_security_group(
    VpcId=VPC_ID,
    GroupName='SG-Backend',
    Description='Security Group for Backend (private)'
)
SG_BACKEND = sg_backend_response['GroupId']

ec2.authorize_security_group_ingress(
    GroupId=SG_BACKEND,
    IpPermissions=[
        {'IpProtocol': '-1', 'UserIdGroupPairs': [{'GroupId': SG_FRONTEND}]},
        {'IpProtocol': 'icmp', 'FromPort': -1, 'ToPort': -1, 'IpRanges': [{'CidrIp': VPC_CIDR}]}
    ]
)
print(f"SG Backend: {SG_BACKEND} (acceso solo desde Frontend)")

# SG Database (solo accesible desde Backend)
sg_database_response = ec2.create_security_group(
    VpcId=VPC_ID,
    GroupName='SG-Database',
    Description='Security Group for Database (private)'
)
SG_DATABASE = sg_database_response['GroupId']

ec2.authorize_security_group_ingress(
    GroupId=SG_DATABASE,
    IpPermissions=[
        {'IpProtocol': 'tcp', 'FromPort': 3306, 'ToPort': 3306, 'UserIdGroupPairs': [{'GroupId': SG_BACKEND}]},
        {'IpProtocol': 'tcp', 'FromPort': 5432, 'ToPort': 5432, 'UserIdGroupPairs': [{'GroupId': SG_BACKEND}]},
        {'IpProtocol': 'icmp', 'FromPort': -1, 'ToPort': -1, 'IpRanges': [{'CidrIp': VPC_CIDR}]}
         {
            'IpProtocol': 'tcp',
            'FromPort': 22,
            'ToPort': 22,
            'UserIdGroupPairs': [
                {'GroupId': SG_BACKEND}
            ]
        }
    ]
)
print(f"SG Database: {SG_DATABASE} (acceso solo desde Backend)")

# ========================================
# 6. CREAR INSTANCIAS EC2
# ========================================
print("\nCreando instancias EC2...")

# Frontend (subred pública)
ec2_frontend_response = ec2.run_instances(
    ImageId='ami-0360c520857e3138f',
    InstanceType='t3.micro',
    KeyName='vockey',
    SubnetId=SUBNET_PUBLIC,
    SecurityGroupIds=[SG_FRONTEND],
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[{
        'ResourceType': 'instance',
        'Tags': [{'Key': 'Name', 'Value': 'EC2-Frontend'}]
    }]
)
EC2_FRONTEND = ec2_frontend_response['Instances'][0]['InstanceId']
print(f"EC2 Frontend (publico): {EC2_FRONTEND}")

# Backend (subred privada)
ec2_backend_response = ec2.run_instances(
    ImageId='ami-0360c520857e3138f',
    InstanceType='t3.micro',
    KeyName='vockey',
    SubnetId=SUBNET_PRIVATE_1,
    SecurityGroupIds=[SG_BACKEND],
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[{
        'ResourceType': 'instance',
        'Tags': [{'Key': 'Name', 'Value': 'EC2-Backend'}]
    }]
)
EC2_BACKEND = ec2_backend_response['Instances'][0]['InstanceId']
print(f"EC2 Backend (privado): {EC2_BACKEND}")

# Database (subred privada)
ec2_database_response = ec2.run_instances(
    ImageId='ami-0360c520857e3138f',
    InstanceType='t3.micro',
    KeyName='vockey',
    SubnetId=SUBNET_PRIVATE_2,
    SecurityGroupIds=[SG_DATABASE],
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[{
        'ResourceType': 'instance',
        'Tags': [{'Key': 'Name', 'Value': 'EC2-Database'}]
    }]
)
EC2_DATABASE = ec2_database_response['Instances'][0]['InstanceId']
print(f"EC2 Database (privada): {EC2_DATABASE}")

# ========================================
# 7. CONFIGURAR TABLAS DE RUTAS
# ========================================
print("\nConfigurando tablas de rutas...")

# Tabla de rutas pública (para Frontend)
rtb_public_response = ec2.create_route_table(
    VpcId=VPC_ID,
    TagSpecifications=[{
        'ResourceType': 'route-table',
        'Tags': [{'Key': 'Name', 'Value': 'RTB-Public'}]
    }]
)
RTB_PUBLIC = rtb_public_response['RouteTable']['RouteTableId']

# Ruta a internet vía IGW
ec2.create_route(
    RouteTableId=RTB_PUBLIC,
    DestinationCidrBlock='0.0.0.0/0',
    GatewayId=IGW_ID
)

# Asociar subred pública
ec2.associate_route_table(SubnetId=SUBNET_PUBLIC, RouteTableId=RTB_PUBLIC)
print(f"Tabla de rutas publica creada: {RTB_PUBLIC}")

# Tabla de rutas privada (para Backend y Database)
rtb_private_response = ec2.create_route_table(
    VpcId=VPC_ID,
    TagSpecifications=[{
        'ResourceType': 'route-table',
        'Tags': [{'Key': 'Name', 'Value': 'RTB-Private'}]
    }]
)
RTB_PRIVATE = rtb_private_response['RouteTable']['RouteTableId']

# Ruta a internet vía NAT Gateway
ec2.create_route(
    RouteTableId=RTB_PRIVATE,
    DestinationCidrBlock='0.0.0.0/0',
    NatGatewayId=NAT_ID
)

# Asociar subredes privadas
ec2.associate_route_table(SubnetId=SUBNET_PRIVATE_1, RouteTableId=RTB_PRIVATE)
ec2.associate_route_table(SubnetId=SUBNET_PRIVATE_2, RouteTableId=RTB_PRIVATE)
print(f"Tabla de rutas privada creada: {RTB_PRIVATE} (salida via NAT)")

# ========================================
# 8. OBTENER IPs
# ========================================
print("\nEsperando que las instancias esten en ejecucion...")
time.sleep(30)

print("\nObteniendo IPs...")

frontend_info = ec2.describe_instances(InstanceIds=[EC2_FRONTEND])
IP_PUBLIC_FRONTEND = frontend_info['Reservations'][0]['Instances'][0].get('PublicIpAddress', 'N/A')
IP_PRIVATE_FRONTEND = frontend_info['Reservations'][0]['Instances'][0]['PrivateIpAddress']

backend_info = ec2.describe_instances(InstanceIds=[EC2_BACKEND])
IP_PRIVATE_BACKEND = backend_info['Reservations'][0]['Instances'][0]['PrivateIpAddress']

database_info = ec2.describe_instances(InstanceIds=[EC2_DATABASE])
IP_PRIVATE_DATABASE = database_info['Reservations'][0]['Instances'][0]['PrivateIpAddress']

# ========================================
# RESUMEN FINAL
# ========================================
print()
print("=" * 60)
print("APLICACION WEB DE 3 CAPAS CREADA EXITOSAMENTE")
print("=" * 60)
print()
print("ARQUITECTURA:")
print("-" * 60)
print(f"VPC: {VPC_ID} ({VPC_CIDR})")
print()
print("FRONTEND (Capa 1 - Publica):")
print(f"  Subred: {SUBNET_PUBLIC} ({SUBNET_PUBLIC_CIDR})")
print(f"  Instancia: {EC2_FRONTEND}")
print(f"  IP Publica: {IP_PUBLIC_FRONTEND}")
print(f"  IP Privada: {IP_PRIVATE_FRONTEND}")
print(f"  Acceso: SSH, HTTP, HTTPS desde internet")
print()
print("BACKEND (Capa 2 - Privada):")
print(f"  Subred: {SUBNET_PRIVATE_1} ({SUBNET_PRIVATE_1_CIDR})")
print(f"  Instancia: {EC2_BACKEND}")
print(f"  IP Privada: {IP_PRIVATE_BACKEND}")
print(f"  Acceso: Solo desde Frontend")
print(f"  Salida Internet: Via NAT Gateway")
print()
print("DATABASE (Capa 3 - Privada):")
print(f"  Subred: {SUBNET_PRIVATE_2} ({SUBNET_PRIVATE_2_CIDR})")
print(f"  Instancia: {EC2_DATABASE}")
print(f"  IP Privada: {IP_PRIVATE_DATABASE}")
print(f"  Acceso: Solo desde Backend")
print(f"  Salida Internet: Via NAT Gateway")
print()
print("-" * 60)
print()
print("CONEXIONES:")
print(f"  ssh -i vockey.pem ec2-user@{IP_PUBLIC_FRONTEND}")
print()
print("=" * 60)