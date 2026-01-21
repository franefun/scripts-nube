import boto3
import time

# ========================================
# CONFIGURACION Y CLIENTES
# ========================================
REGION_1 = "us-east-1"      # Virginia
REGION_2 = "us-west-2"      # Oregon
AMI_VIRGINIA = "ami-0360c520857e3138f" 
AMI_OREGON = "ami-00f46ccd1cbfb363e"   
KEY_V = "vockey"            
KEY_O = "my-key-pair"       

ec2_r1 = boto3.client('ec2', region_name=REGION_1)
ec2_r2 = boto3.client('ec2', region_name=REGION_2)
sts = boto3.client('sts')
account_id = sts.get_caller_identity()['Account']

print("=========================================")
print("INICIANDO CREACION DE INFRAESTRUCTURA MULTI-REGION")
print("=========================================")

# ========================================
# REGION 1: VIRGINIA
# ========================================
print("CONFIGURANDO REGION 1: VIRGINIA")

# VPC-A y VPC-B
vpc_a = ec2_r1.create_vpc(CidrBlock='10.10.0.0/16', TagSpecifications=[{'ResourceType': 'vpc', 'Tags': [{'Key': 'Name', 'Value': 'VPC-A-Virginia'}]}])['Vpc']['VpcId']
ec2_r1.modify_vpc_attribute(VpcId=vpc_a, EnableDnsHostnames={'Value': True})

vpc_b = ec2_r1.create_vpc(CidrBlock='10.20.0.0/16', TagSpecifications=[{'ResourceType': 'vpc', 'Tags': [{'Key': 'Name', 'Value': 'VPC-B-Virginia'}]}])['Vpc']['VpcId']
ec2_r1.modify_vpc_attribute(VpcId=vpc_b, EnableDnsHostnames={'Value': True})

# Internet Gateway VPC-A
igw_a = ec2_r1.create_internet_gateway(TagSpecifications=[{'ResourceType': 'internet-gateway', 'Tags': [{'Key': 'Name', 'Value': 'IGW-A-Virginia'}]}])['InternetGateway']['InternetGatewayId']
ec2_r1.attach_internet_gateway(InternetGatewayId=igw_a, VpcId=vpc_a)

# Subredes VPC-A
sub_a_pub = ec2_r1.create_subnet(VpcId=vpc_a, CidrBlock='10.10.1.0/24', AvailabilityZone=f"{REGION_1}a", TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-A-Public-1'}]}])['Subnet']['SubnetId']
ec2_r1.modify_subnet_attribute(SubnetId=sub_a_pub, MapPublicIpOnLaunch={'Value': True})
sub_a_priv1 = ec2_r1.create_subnet(VpcId=vpc_a, CidrBlock='10.10.3.0/24', AvailabilityZone=f"{REGION_1}a", TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-A-Private-1'}]}])['Subnet']['SubnetId']
sub_a_priv2 = ec2_r1.create_subnet(VpcId=vpc_a, CidrBlock='10.10.4.0/24', AvailabilityZone=f"{REGION_1}b", TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-A-Private-2'}]}])['Subnet']['SubnetId']

# Subredes VPC-B
sub_b_priv1 = ec2_r1.create_subnet(VpcId=vpc_b, CidrBlock='10.20.1.0/24', AvailabilityZone=f"{REGION_1}a", TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-B-Private-1'}]}])['Subnet']['SubnetId']
sub_b_priv2 = ec2_r1.create_subnet(VpcId=vpc_b, CidrBlock='10.20.2.0/24', AvailabilityZone=f"{REGION_1}b", TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-B-Private-2'}]}])['Subnet']['SubnetId']

# Security Groups Virginia
sg_a_pub = ec2_r1.create_security_group(GroupName='SG-A-Public-Virginia', Description="Public SG for VPC-A Virginia", VpcId=vpc_a)['GroupId']
ec2_r1.authorize_security_group_ingress(GroupId=sg_a_pub, IpPermissions=[
    {'IpProtocol': 'tcp', 'FromPort': 22, 'ToPort': 22, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]},
    {'IpProtocol': 'icmp', 'FromPort': -1, 'ToPort': -1, 'IpRanges': [{'CidrIp': '0.0.0.0/0'}]}
])

# NAT Gateway Virginia
eip_v = ec2_r1.allocate_address(Domain='vpc')['AllocationId']
nat_v = ec2_r1.create_nat_gateway(SubnetId=sub_a_pub, AllocationId=eip_v, TagSpecifications=[{'ResourceType': 'natgateway', 'Tags': [{'Key': 'Name', 'Value': 'NAT-Virginia'}]}])['NatGateway']['NatGatewayId']
print("Esperando NAT Gateway Virginia...")
ec2_r1.get_waiter('nat_gateway_available').wait(NatGatewayIds=[nat_v])

# ========================================
# TRANSIT GATEWAY VIRGINIA
# ========================================
tgw_v = ec2_r1.create_transit_gateway(Description="TGW Virginia", TagSpecifications=[{'ResourceType': 'transit-gateway', 'Tags': [{'Key': 'Name', 'Value': 'TGW-Virginia'}]}])['TransitGateway']['TransitGatewayId']
print("Esperando TGW Virginia (180s)...")
time.sleep(180)

# Attachments Virginia
ec2_r1.create_transit_gateway_vpc_attachment(TransitGatewayId=tgw_v, VpcId=vpc_a, SubnetIds=[sub_a_priv1, sub_a_priv2], TagSpecifications=[{'ResourceType': 'transit-gateway-attachment', 'Tags': [{'Key': 'Name', 'Value': 'TGW-Attach-VPC-A'}]}])
ec2_r1.create_transit_gateway_vpc_attachment(TransitGatewayId=tgw_v, VpcId=vpc_b, SubnetIds=[sub_b_priv1, sub_b_priv2], TagSpecifications=[{'ResourceType': 'transit-gateway-attachment', 'Tags': [{'Key': 'Name', 'Value': 'TGW-Attach-VPC-B'}]}])

# ========================================
# REGION 2: OREGON
# ========================================
print("CONFIGURANDO REGION 2: OREGON")

# VPC-C y VPC-D
vpc_c = ec2_r2.create_vpc(CidrBlock='10.30.0.0/16', TagSpecifications=[{'ResourceType': 'vpc', 'Tags': [{'Key': 'Name', 'Value': 'VPC-C-Oregon'}]}])['Vpc']['VpcId']
ec2_r2.modify_vpc_attribute(VpcId=vpc_c, EnableDnsHostnames={'Value': True})

vpc_d = ec2_r2.create_vpc(CidrBlock='10.40.0.0/16', TagSpecifications=[{'ResourceType': 'vpc', 'Tags': [{'Key': 'Name', 'Value': 'VPC-D-Oregon'}]}])['Vpc']['VpcId']
ec2_r2.modify_vpc_attribute(VpcId=vpc_d, EnableDnsHostnames={'Value': True})

# Internet Gateway VPC-C
igw_c = ec2_r2.create_internet_gateway(TagSpecifications=[{'ResourceType': 'internet-gateway', 'Tags': [{'Key': 'Name', 'Value': 'IGW-C-Oregon'}]}])['InternetGateway']['InternetGatewayId']
ec2_r2.attach_internet_gateway(InternetGatewayId=igw_c, VpcId=vpc_c)

# Subredes VPC-C y VPC-D
sub_c_pub = ec2_r2.create_subnet(VpcId=vpc_c, CidrBlock='10.30.1.0/24', TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-C-Public-1'}]}])['Subnet']['SubnetId']
ec2_r2.modify_subnet_attribute(SubnetId=sub_c_pub, MapPublicIpOnLaunch={'Value': True})
sub_c_priv1 = ec2_r2.create_subnet(VpcId=vpc_c, CidrBlock='10.30.3.0/24', TagSpecifications=[{'ResourceType': 'subnet', 'Tags': [{'Key': 'Name', 'Value': 'VPC-C-Private-1'}]}])['Subnet']['SubnetId']

# Transit Gateway Oregon
tgw_o = ec2_r2.create_transit_gateway(Description="TGW Oregon", TagSpecifications=[{'ResourceType': 'transit-gateway', 'Tags': [{'Key': 'Name', 'Value': 'TGW-Oregon'}]}])['TransitGateway']['TransitGatewayId']
print("Esperando TGW Oregon (180s)...")
time.sleep(180)

# ========================================
# TRANSIT GATEWAY PEERING
# ========================================
peering = ec2_r1.create_transit_gateway_peering_attachment(
    TransitGatewayId=tgw_v, 
    PeerTransitGatewayId=tgw_o, 
    PeerRegion=REGION_2, 
    PeerAccountId=account_id,
    TagSpecifications=[{'ResourceType': 'transit-gateway-attachment', 'Tags': [{'Key': 'Name', 'Value': 'TGW-Peering-Virginia-Oregon'}]}]
)['TransitGatewayPeeringAttachment']['TransitGatewayAttachmentId']

print("Esperando aceptacion de peering (120s)...")
time.sleep(120)
ec2_r2.accept_transit_gateway_peering_attachment(TransitGatewayAttachmentId=peering)
print("Esperando disponibilidad de peering (300s)...")
time.sleep(300)

# ========================================
# INSTANCIAS EC2
# ========================================
print("Lanzando instancias EC2...")
ec2_v_pub = ec2_r1.run_instances(
    ImageId=AMI_VIRGINIA, InstanceType='t3.micro', KeyName=KEY_V, MaxCount=1, MinCount=1,
    NetworkInterfaces=[{'SubnetId': sub_a_pub, 'DeviceIndex': 0, 'AssociatePublicIpAddress': True, 'Groups': [sg_a_pub]}],
    TagSpecifications=[{'ResourceType': 'instance', 'Tags': [{'Key': 'Name', 'Value': 'EC2-Virginia-Public'}]}]
)

print("Infraestructura completa.")