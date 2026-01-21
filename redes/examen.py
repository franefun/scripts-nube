import boto3
import time

ec2 = boto3.client('ec2', region_name='us-east-1')

########################################
# 1. Crear VPC
########################################
vpc = ec2.create_vpc(CidrBlock='10.10.0.0/16', TagSpecifications=[{
    'ResourceType': 'vpc',
    'Tags': [{'Key': 'Name', 'Value': 'VPC-Examen'}]
}])
VPC_ID = vpc['Vpc']['VpcId']
ec2.modify_vpc_attribute(VpcId=VPC_ID, EnableDnsHostnames={'Value': True})
print(f"VPC creada: {VPC_ID}")

########################################
# 2. Internet Gateway
########################################
igw = ec2.create_internet_gateway()
IGW_ID = igw['InternetGateway']['InternetGatewayId']
ec2.attach_internet_gateway(InternetGatewayId=IGW_ID, VpcId=VPC_ID)
print(f"Internet Gateway: {IGW_ID}")

########################################
# 3. Crear Subredes
########################################
subnets = {}
subnets['PUB1'] = ec2.create_subnet(VpcId=VPC_ID, CidrBlock='10.10.1.0/24', AvailabilityZone='us-east-1a',
                                    TagSpecifications=[{'ResourceType':'subnet','Tags':[{'Key':'Name','Value':'Public-1'}]}])['Subnet']['SubnetId']
ec2.modify_subnet_attribute(SubnetId=subnets['PUB1'], MapPublicIpOnLaunch={'Value': True})
subnets['PUB2'] = ec2.create_subnet(VpcId=VPC_ID, CidrBlock='10.10.2.0/24', AvailabilityZone='us-east-1b',
                                    TagSpecifications=[{'ResourceType':'subnet','Tags':[{'Key':'Name','Value':'Public-2'}]}])['Subnet']['SubnetId']
ec2.modify_subnet_attribute(SubnetId=subnets['PUB2'], MapPublicIpOnLaunch={'Value': True})
subnets['PRIV1'] = ec2.create_subnet(VpcId=VPC_ID, CidrBlock='10.10.3.0/24', AvailabilityZone='us-east-1a',
                                     TagSpecifications=[{'ResourceType':'subnet','Tags':[{'Key':'Name','Value':'Private-1'}]}])['Subnet']['SubnetId']
subnets['PRIV2'] = ec2.create_subnet(VpcId=VPC_ID, CidrBlock='10.10.4.0/24', AvailabilityZone='us-east-1b',
                                     TagSpecifications=[{'ResourceType':'subnet','Tags':[{'Key':'Name','Value':'Private-2'}]}])['Subnet']['SubnetId']

print("Subredes creadas:", subnets)

########################################
# 4. Tablas de rutas públicas
########################################
rtb_pub1 = ec2.create_route_table(VpcId=VPC_ID)['RouteTable']['RouteTableId']
ec2.create_route(RouteTableId=rtb_pub1, DestinationCidrBlock='0.0.0.0/0', GatewayId=IGW_ID)
ec2.associate_route_table(RouteTableId=rtb_pub1, SubnetId=subnets['PUB1'])

rtb_pub2 = ec2.create_route_table(VpcId=VPC_ID)['RouteTable']['RouteTableId']
ec2.create_route(RouteTableId=rtb_pub2, DestinationCidrBlock='0.0.0.0/0', GatewayId=IGW_ID)
ec2.associate_route_table(RouteTableId=rtb_pub2, SubnetId=subnets['PUB2'])

########################################
# 5. NAT Gateway en Public-1
########################################
eip = ec2.allocate_address(Domain='vpc')
EIP_ID = eip['AllocationId']

nat = ec2.create_nat_gateway(SubnetId=subnets['PUB1'], AllocationId=EIP_ID)
NAT_ID = nat['NatGateway']['NatGatewayId']
print("Creando NAT...")
waiter = ec2.get_waiter('nat_gateway_available')
waiter.wait(NatGatewayIds=[NAT_ID])
print(f"NAT creado: {NAT_ID}")

########################################
# 6. Tablas de rutas privadas
########################################
rtb_priv1 = ec2.create_route_table(VpcId=VPC_ID)['RouteTable']['RouteTableId']
ec2.create_route(RouteTableId=rtb_priv1, DestinationCidrBlock='0.0.0.0/0', NatGatewayId=NAT_ID)
ec2.associate_route_table(RouteTableId=rtb_priv1, SubnetId=subnets['PRIV1'])

rtb_priv2 = ec2.create_route_table(VpcId=VPC_ID)['RouteTable']['RouteTableId']
ec2.create_route(RouteTableId=rtb_priv2, DestinationCidrBlock='0.0.0.0/0', NatGatewayId=NAT_ID)
ec2.associate_route_table(RouteTableId=rtb_priv2, SubnetId=subnets['PRIV2'])

########################################
# 7. Security Groups
########################################
sg_pub = ec2.create_security_group(VpcId=VPC_ID, GroupName='SG-PUBLIC', Description='SG Public')['GroupId']
ec2.authorize_security_group_ingress(GroupId=sg_pub, IpProtocol='tcp', FromPort=22, ToPort=22, CidrIp='0.0.0.0/0')
ec2.authorize_security_group_ingress(GroupId=sg_pub, IpProtocol='tcp', FromPort=80, ToPort=80, CidrIp='0.0.0.0/0')
ec2.authorize_security_group_ingress(GroupId=sg_pub, IpProtocol='tcp', FromPort=443, ToPort=443, CidrIp='0.0.0.0/0')

sg_priv = ec2.create_security_group(VpcId=VPC_ID, GroupName='SG-PRIVATE', Description='SG Private')['GroupId']
ec2.authorize_security_group_ingress(GroupId=sg_priv, IpProtocol='-1', SourceSecurityGroupName='SG-PUBLIC', SourceSecurityGroupOwnerId=vpc['Vpc']['OwnerId'])

########################################
# 8. EC2
########################################
ami_id = 'ami-0360c520857e3138f'
key_name = 'vockey'

# Pública 1
ec2_pub1 = ec2.run_instances(ImageId=ami_id, InstanceType='t3.micro', KeyName=key_name, MaxCount=1, MinCount=1,
                             SubnetId=subnets['PUB1'], SecurityGroupIds=[sg_pub],
                             TagSpecifications=[{'ResourceType':'instance','Tags':[{'Key':'Name','Value':'miEc2-publica-1'}]}],
                             AssociatePublicIpAddress=True)['Instances'][0]['InstanceId']

# Privada 1
ec2_priv1 = ec2.run_instances(ImageId=ami_id, InstanceType='t3.micro', KeyName=key_name, MaxCount=1, MinCount=1,
                              SubnetId=subnets['PRIV1'], SecurityGroupIds=[sg_priv],
                              TagSpecifications=[{'ResourceType':'instance','Tags':[{'Key':'Name','Value':'miEc2-privada-1'}]}])['Instances'][0]['InstanceId']

# Pública 2
ec2_pub2 = ec2.run_instances(ImageId=ami_id, InstanceType='t3.micro', KeyName=key_name, MaxCount=1, MinCount=1,
                             SubnetId=subnets['PUB2'], SecurityGroupIds=[sg_pub],
                             TagSpecifications=[{'ResourceType':'instance','Tags':[{'Key':'Name','Value':'miEc2-publica-2'}]}],
                             AssociatePublicIpAddress=True)['Instances'][0]['InstanceId']

# Privada 2
ec2_priv2 = ec2.run_instances(ImageId=ami_id, InstanceType='t3.micro', KeyName=key_name, MaxCount=1, MinCount=1,
                              SubnetId=subnets['PRIV2'], SecurityGroupIds=[sg_priv],
                              TagSpecifications=[{'ResourceType':'instance','Tags':[{'Key':'Name','Value':'miEc2-privada-2'}]}])['Instances'][0]['InstanceId']

print("EC2 creadas.")

########################################
# 9. NACLs
########################################
# Pública
nacl_pub = ec2.create_network_acl(VpcId=VPC_ID, TagSpecifications=[{'ResourceType':'network-acl','Tags':[{'Key':'Name','Value':'NACL-Publica'}]}])['NetworkAcl']['NetworkAclId']
ec2.create_network_acl_entry(NetworkAclId=nacl_pub, RuleNumber=100, Protocol='6', RuleAction='allow', Egress=False, PortRange={'From':22,'To':22}, CidrBlock='0.0.0.0/0')
ec2.create_network_acl_entry(NetworkAclId=nacl_pub, RuleNumber=110, Protocol='6', RuleAction='allow', Egress=False, PortRange={'From':80,'To':80}, CidrBlock='0.0.0.0/0')
ec2.create_network_acl_entry(NetworkAclId=nacl_pub, RuleNumber=120, Protocol='6', RuleAction='allow', Egress=False, PortRange={'From':443,'To':443}, CidrBlock='0.0.0.0/0')
ec2.create_network_acl_entry(NetworkAclId=nacl_pub, RuleNumber=100, Protocol='-1', RuleAction='allow', Egress=True, CidrBlock='0.0.0.0/0')

# Privada
nacl_priv = ec2.create_network_acl(VpcId=VPC_ID, TagSpecifications=[{'ResourceType':'network-acl','Tags':[{'Key':'Name','Value':'NACL-Privada'}]}])['NetworkAcl']['NetworkAclId']
ec2.create_network_acl_entry(NetworkAclId=nacl_priv, RuleNumber=100, Protocol='-1', RuleAction='allow', Egress=False, CidrBlock='10.10.0.0/16')
ec2.create_network_acl_entry(NetworkAclId=nacl_priv, RuleNumber=110, Protocol='-1', RuleAction='deny', Egress=False, CidrBlock='0.0.0.0/0')
ec2.create_network_acl_entry(NetworkAclId=nacl_priv, RuleNumber=100, Protocol='-1', RuleAction='allow', Egress=True, CidrBlock='10.10.0.0/16')

# Asociar NACLs a subredes
for subnet_id in [subnets['PUB1'], subnets['PUB2']]:
    assoc = ec2.describe_network_acls(Filters=[{'Name':'association.subnet-id','Values':[subnet_id]}])['NetworkAcls'][0]['Associations'][0]['NetworkAclAssociationId']
    ec2.replace_network_acl_association(AssociationId=assoc, NetworkAclId=nacl_pub)

for subnet_id in [subnets['PRIV1'], subnets['PRIV2']]:
    assoc = ec2.describe_network_acls(Filters=[{'Name':'association.subnet-id','Values':[subnet_id]}])['NetworkAcls'][0]['Associations'][0]['NetworkAclAssociationId']
    ec2.replace_network_acl_association(AssociationId=assoc, NetworkAclId=nacl_priv)

print("NACLs asociadas")
print("Infraestructura completa desplegada.")
