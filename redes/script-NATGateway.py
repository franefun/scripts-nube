import boto3
import time

# Crear cliente EC2
ec2 = boto3.client('ec2')

# Crear la VPC
vpc_response = ec2.create_vpc(
    CidrBlock='192.168.0.0/16',
    TagSpecifications=[
        {
            'ResourceType': 'vpc',
            'Tags': [{'Key': 'Name', 'Value': 'MyVpc'}]
        }
    ]
)
vpc_id = vpc_response['Vpc']['VpcId']
print(f"VPC creada con ID: {vpc_id}")

print("--------------------------------")

# Habilitar DNS en la VPC
ec2.modify_vpc_attribute(
    VpcId=vpc_id,
    EnableDnsHostnames={'Value': True}
)
print("DNS hostnames habilitados en la VPC.")

print("--------------------------------")

subnet_publica= ec2.create_subnet(
    VpcId=vpc_id,
    CidrBlock='192.168.0.0/24',
    AvailabilityZone='us-east-1a',
    TagSpecifications=[
        {
            'ResourceType': 'subnet',
            'Tags': [{'Key': 'Name', 'Value': 'MiSubred-publica'}]
        }
    ]
)
subnet_id_publica = subnet_publica['Subnet']['SubnetId']

# Habilitar IP pública automática en la subred
ec2.modify_subnet_attribute(
    SubnetId=subnet_id_publica,
    MapPublicIpOnLaunch={'Value': True}
)
print(f"Subred pública creada con ID: {subnet_id_publica}")

print("--------------------------------")

subnet_privada= ec2.create_subnet(
    VpcId=vpc_id,
    CidrBlock='192.168.1.0/24',
    AvailabilityZone='us-east-1a',
    TagSpecifications=[
        {
            'ResourceType': 'subnet',
            'Tags': [{'Key': 'Name', 'Value': 'MiSubred-privada'}]
        }
    ]
)
subnet_id_privada = subnet_privada['Subnet']['SubnetId']
print(f"Subred privada creada con ID: {subnet_id_privada}")

print("--------------------------------")

# Creo internet Gateway y lo asocio a la vpc
igw= ec2.create_internet_gateway()
igw_id = igw['InternetGateway']['InternetGatewayId']
ec2.attach_internet_gateway(InternetGatewayId=igw_id,VpcId=vpc_id)
ec2.create_tags(
    Resources=[igw_id],
    Tags=[{'Key': 'Name', 'Value': 'MiIGW'}]
)
print(f"Internet Gateway creado y asociado a la VPC: {igw_id}")

print("--------------------------------")

# Creo tabla de rutas
route_table=ec2.create_route_table (VpcId=vpc_id)
rtb_id = route_table['RouteTable']['RouteTableId']
print(f"Tabla de rutas creada: {rtb_id}")

print("--------------------------------")

# Creo ruta hacia Internet
ec2.create_route(
    RouteTableId=rtb_id,
    DestinationCidrBlock='0.0.0.0/0',
    GatewayId=igw_id
)
print(f"Ruta a Internet creada en la tabla {rtb_id}")

print("--------------------------------")

# Asociar la tabla de rutas a la subred pública
association = ec2.associate_route_table(
    SubnetId=subnet_id_publica,
    RouteTableId=rtb_id
)
print(f"Tabla de rutas {rtb_id} asociada a la subred {subnet_id_publica}")

print("--------------------------------")

# Crear Security Group
gs=ec2.create_security_group(
    Description='grupo de seguridad para mi VPC',
    GroupName='gs-NatGateway',
    VpcId=vpc_id)
sg_id = gs['GroupId']
print(f"Grupo de seguridad creado con ID: {sg_id}")


print("--------------------------------")

# Reglas del grupo de seguridad
ec2.authorize_security_group_ingress(
    GroupId=sg_id,
    IpPermissions=[
        {
            'IpProtocol': 'tcp',
            'FromPort': 22,
            'ToPort': 22,
            'IpRanges': [
                {'CidrIp': '0.0.0.0/0', 'Description': 'SSH desde cualquier IP'}
            ]
        }
    ]
)

ec2.authorize_security_group_ingress(
    GroupId=sg_id,
    IpPermissions=[
        {
            'IpProtocol': 'icmp',
            'FromPort': -1,
            'ToPort': -1,
            'IpRanges': [
                {'CidrIp': '0.0.0.0/0', 'Description': 'ping desde cualquier IP'}
            ]
        }
    ]
)

# Crear instancia EC2 en la subred pública
ec2_publica = ec2.run_instances(
    ImageId='ami-0360c520857e3138f',
    InstanceType='t3.micro',
    KeyName='vockey',
    SubnetId=subnet_id_publica,
    SecurityGroupIds=[sg_id],
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[
        {
            'ResourceType': 'instance',
            'Tags': [{'Key': 'Name', 'Value': 'Ec2-publica'}]
        }
    ]
)

ec2_publica_id = ec2_publica['Instances'][0]['InstanceId']
print(f"Instancia EC2 pública creada con ID: {ec2_publica_id}")

print("--------------------------------")

# Crear instancia EC2 en la subred privada
ec2_privada = ec2.run_instances(
    ImageId='ami-0360c520857e3138f',
    InstanceType='t3.micro',
    KeyName='vockey',
    SubnetId=subnet_id_privada,
    SecurityGroupIds=[sg_id],
    MinCount=1,
    MaxCount=1,
    TagSpecifications=[
        {
            'ResourceType': 'instance',
            'Tags': [{'Key': 'Name', 'Value': 'Ec2-privada'}]
        }
    ]
)

ec2_privada_id = ec2_privada['Instances'][0]['InstanceId']
print(f"Instancia EC2 privada creada con ID: {ec2_privada_id}")

print("--------------------------------")

# Crear Elastic IP para el NAT Gateway
eip = ec2.allocate_address(Domain='vpc')
eip_id = eip['AllocationId']

print(f"Elastic IP creada con ID: {eip_id}")

print("--------------------------------")

# Crear NAT Gateway en la subred pública
nat_gateway = ec2.create_nat_gateway(
    SubnetId=subnet_id_publica, 
    AllocationId=eip_id,
    TagSpecifications=[
        {
            'ResourceType': 'natgateway',
            'Tags': [{'Key': 'Name', 'Value': 'MiNATGateway'}]
        }
    ]
)
nat_gateway_id = nat_gateway['NatGateway']['NatGatewayId']
print(f"NAT Gateway creada con ID: {nat_gateway_id}")

print("--------------------------------")

# Esperar a que el NAT Gateway esté disponible
waiter = ec2.get_waiter('nat_gateway_available')
waiter.wait(NatGatewayIds=[nat_gateway_id])


#Creo tabla de rutas para la subred privada
rtb_privada = ec2.create_route_table(
    VpcId=vpc_id, 
    TagSpecifications=[
        {
            'ResourceType': 'route-table',
            'Tags': [{'Key': 'Name', 'Value': 'MiRouteTable-privada'}]
        }
    ]
)
rtb_privada_id = rtb_privada['RouteTable']['RouteTableId']
print(f"Tabla de rutas privada creada con ID: {rtb_privada_id}")

print("--------------------------------")

#Añado la ruta hacia el NAT Gateway
ec2.create_route(
    RouteTableId=rtb_privada_id,
    DestinationCidrBlock='0.0.0.0/0',
    NatGatewayId=nat_gateway_id

)
print("Ruta hacia el NAT Gateway añadida a la tabla de rutas privada")
print("--------------------------------")

#Asocia la tabla de rutas a la subred privada
ec2.associate_route_table(
    SubnetId=subnet_id_privada,
    RouteTableId=rtb_privada_id
)

print("Tabla de rutas asociada a la subred privada")






