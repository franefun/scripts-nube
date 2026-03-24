#!/usr/bin/env python3
"""
Script para ELIMINAR toda la infraestructura AWS creada

Este script elimina en el orden correcto:
1. Instancias EC2 (y espera a que terminen)
2. Security Groups
3. Desasocia y elimina Route Tables
4. Desadjunta y elimina Internet Gateways
5. Elimina Subnets
6. Elimina VPCs

ADVERTENCIA: Este script eliminará TODOS los recursos que coincidan con los nombres
especificados. Úsalo con precaución.

Requisitos:
    pip install boto3

Uso:
    py eliminar_infraestructura.py
"""

import boto3
import time
from botocore.exceptions import ClientError

def wait_for_instance_termination(ec2, instance_ids):
    """Espera a que las instancias EC2 terminen completamente"""
    if not instance_ids:
        return
    
    print(f"  Esperando a que las instancias terminen: {', '.join(instance_ids)}")
    waiter = ec2.get_waiter('instance_terminated')
    try:
        waiter.wait(InstanceIds=instance_ids)
        print("  ✓ Instancias terminadas")
    except Exception as e:
        print(f"  ⚠ Error esperando terminación: {e}")

def delete_instances(ec2):
    """Elimina todas las instancias EC2 con el tag Name=miec2"""
    print("\n[1/6] Eliminando instancias EC2...")
    try:
        # Buscar instancias con el tag Name=miec2
        response = ec2.describe_instances(
            Filters=[
                {'Name': 'tag:Name', 'Values': ['miec2']},
                {'Name': 'instance-state-name', 'Values': ['running', 'stopped', 'pending', 'stopping']}
            ]
        )
        
        instance_ids = []
        for reservation in response['Reservations']:
            for instance in reservation['Instances']:
                instance_ids.append(instance['InstanceId'])
        
        if instance_ids:
            print(f"  Encontradas {len(instance_ids)} instancia(s): {', '.join(instance_ids)}")
            ec2.terminate_instances(InstanceIds=instance_ids)
            print(f"  ✓ Solicitud de terminación enviada")
            wait_for_instance_termination(ec2, instance_ids)
        else:
            print("  ℹ No se encontraron instancias EC2 para eliminar")
    except ClientError as e:
        print(f"  ⚠ Error: {e}")

def delete_security_groups(ec2):
    """Elimina Security Groups con el nombre gsmio"""
    print("\n[2/6] Eliminando Security Groups...")
    try:
        # Buscar security groups con el nombre gsmio
        response = ec2.describe_security_groups(
            Filters=[{'Name': 'group-name', 'Values': ['gsmio']}]
        )
        
        for sg in response['SecurityGroups']:
            sg_id = sg['GroupId']
            print(f"  Eliminando Security Group: {sg_id}")
            ec2.delete_security_group(GroupId=sg_id)
            print(f"  ✓ Security Group {sg_id} eliminado")
    except ClientError as e:
        if 'does not exist' in str(e):
            print("  ℹ No se encontraron Security Groups para eliminar")
        else:
            print(f"  ⚠ Error: {e}")

def delete_route_tables(ec2):
    """Elimina Route Tables con el tag Name=MiTablaEnrutadora"""
    print("\n[3/6] Eliminando Route Tables...")
    try:
        # Buscar route tables con el tag Name=MiTablaEnrutadora
        response = ec2.describe_route_tables(
            Filters=[{'Name': 'tag:Name', 'Values': ['MiTablaEnrutadora']}]
        )
        
        for rt in response['RouteTables']:
            rt_id = rt['RouteTableId']
            print(f"  Procesando Route Table: {rt_id}")
            
            # Desasociar de subnets
            for association in rt['Associations']:
                if not association.get('Main', False):  # No desasociar la ruta principal
                    assoc_id = association['RouteTableAssociationId']
                    print(f"    Desasociando: {assoc_id}")
                    ec2.disassociate_route_table(AssociationId=assoc_id)
                    print(f"    ✓ Desasociado")
            
            # Eliminar la route table
            print(f"  Eliminando Route Table: {rt_id}")
            ec2.delete_route_table(RouteTableId=rt_id)
            print(f"  ✓ Route Table {rt_id} eliminada")
    except ClientError as e:
        if 'does not exist' in str(e):
            print("  ℹ No se encontraron Route Tables para eliminar")
        else:
            print(f"  ⚠ Error: {e}")

def delete_internet_gateways(ec2):
    """Elimina Internet Gateways con el tag Name=MiIg"""
    print("\n[4/6] Eliminando Internet Gateways...")
    try:
        # Buscar internet gateways con el tag Name=MiIg
        response = ec2.describe_internet_gateways(
            Filters=[{'Name': 'tag:Name', 'Values': ['MiIg']}]
        )
        
        for igw in response['InternetGateways']:
            igw_id = igw['InternetGatewayId']
            print(f"  Procesando Internet Gateway: {igw_id}")
            
            # Desadjuntar de VPCs
            for attachment in igw['Attachments']:
                vpc_id = attachment['VpcId']
                print(f"    Desadjuntando de VPC: {vpc_id}")
                ec2.detach_internet_gateway(InternetGatewayId=igw_id, VpcId=vpc_id)
                print(f"    ✓ Desadjuntado")
            
            # Eliminar el internet gateway
            print(f"  Eliminando Internet Gateway: {igw_id}")
            ec2.delete_internet_gateway(InternetGatewayId=igw_id)
            print(f"  ✓ Internet Gateway {igw_id} eliminado")
    except ClientError as e:
        if 'does not exist' in str(e):
            print("  ℹ No se encontraron Internet Gateways para eliminar")
        else:
            print(f"  ⚠ Error: {e}")

def delete_subnets(ec2):
    """Elimina Subnets con el tag Name=mi-subred-lucas1"""
    print("\n[5/6] Eliminando Subnets...")
    try:
        # Buscar subnets con el tag Name=mi-subred-lucas1
        response = ec2.describe_subnets(
            Filters=[{'Name': 'tag:Name', 'Values': ['mi-subred-lucas1']}]
        )
        
        for subnet in response['Subnets']:
            subnet_id = subnet['SubnetId']
            print(f"  Eliminando Subnet: {subnet_id}")
            ec2.delete_subnet(SubnetId=subnet_id)
            print(f"  ✓ Subnet {subnet_id} eliminada")
    except ClientError as e:
        if 'does not exist' in str(e):
            print("  ℹ No se encontraron Subnets para eliminar")
        else:
            print(f"  ⚠ Error: {e}")

def delete_vpcs(ec2):
    """Elimina VPCs con el tag Name=MyVpc"""
    print("\n[6/6] Eliminando VPCs...")
    try:
        # Buscar VPCs con el tag Name=MyVpc
        response = ec2.describe_vpcs(
            Filters=[{'Name': 'tag:Name', 'Values': ['MyVpc']}]
        )
        
        for vpc in response['Vpcs']:
            vpc_id = vpc['VpcId']
            print(f"  Eliminando VPC: {vpc_id}")
            ec2.delete_vpc(VpcId=vpc_id)
            print(f"  ✓ VPC {vpc_id} eliminada")
    except ClientError as e:
        if 'does not exist' in str(e):
            print("  ℹ No se encontraron VPCs para eliminar")
        else:
            print(f"  ⚠ Error: {e}")

def main():
    print("="*60)
    print("ELIMINACIÓN DE INFRAESTRUCTURA AWS")
    print("="*60)
    print("\n⚠️  ADVERTENCIA: Este script eliminará todos los recursos")
    print("    que coincidan con los nombres especificados.")
    print("\nRecursos a eliminar:")
    print("  - Instancias EC2 (Name=miec2)")
    print("  - Security Groups (Name=gsmio)")
    print("  - Route Tables (Name=MiTablaEnrutadora)")
    print("  - Internet Gateways (Name=MiIg)")
    print("  - Subnets (Name=mi-subred-lucas1)")
    print("  - VPCs (Name=MyVpc)")
    
    # Confirmación del usuario
    confirmacion = input("\n¿Deseas continuar? (escribe 'SI' para confirmar): ")
    if confirmacion.upper() != 'SI':
        print("\n❌ Operación cancelada por el usuario")
        return 1
    
    try:
        # Inicializar cliente EC2
        print("\nInicializando cliente EC2...")
        ec2 = boto3.client('ec2')
        
        # Eliminar recursos en el orden correcto
        delete_instances(ec2)
        time.sleep(2)  # Pequeña pausa para asegurar que las instancias estén terminando
        
        delete_security_groups(ec2)
        delete_route_tables(ec2)
        delete_internet_gateways(ec2)
        delete_subnets(ec2)
        delete_vpcs(ec2)
        
        # Resumen final
        print("\n" + "="*60)
        print("ELIMINACIÓN COMPLETADA")
        print("="*60)
        print("✓ Todos los recursos han sido eliminados exitosamente")
        print("="*60)
        
    except ClientError as e:
        print(f"\n❌ Error de AWS: {e}")
        return 1
    except Exception as e:
        print(f"\n❌ Error inesperado: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())