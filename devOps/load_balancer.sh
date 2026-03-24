

#Obtener VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --query "Vpcs[0].VpcId" \
  --output text)
echo "VPC detectada: $VPC_ID"

#Obtener subnets
SUBNETS=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" \
            "Name=instance-state-name,Values=running" \
            "Name=tag:Name,Values=green,blue" \
  --query "Reservations[].Instances[].SubnetId" \
  --output text | tr '\t' ' ')
  
echo "Subnets detectadas: $SUBNETS"

#Crear Security Group
SG_ID=$(aws ec2 create-security-group \
  --group-name "gs-lbCLI" \
  --description "Security group para Load Balancer" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

  echo "Security Group creado: $SG_ID"

  #Configurar regla de ingreso al Security Group
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

echo "Regla de ingreso añadida al Security Group de las instancias."

#Crear Load Balancer
LB_ARN=$(aws elbv2 create-load-balancer \
  --name "lb-CLIFran" \
  --subnets $SUBNETS \
  --type network \
  --security-groups $SG_ID \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)
echo "Load Balancer creado: $LB_ARN"

#Crear Target Group
TG_ARN=$(aws elbv2 create-target-group \
  --name "tg-CLI" \
  --protocol TCP \
  --port 80 \
  --vpc-id $VPC_ID \
  --target-type instance \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)
echo "Target Group creado: $TG_ARN"

#Detectar instancias activas
INSTANCES=$(aws ec2 describe-instances \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text)
echo "Instancias detectadas: $INSTANCES"

#Registrar instancias
  aws elbv2 register-targets \
    --target-group-arn $TG_ARN \
    --targets $(for id in $INSTANCES; do echo "Id=$id"; done)
  echo "Instancias registradas en el Target Group."

#Crear Listener TCP
aws elbv2 create-listener \
  --load-balancer-arn $LB_ARN \
  --protocol TCP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN
echo "Listener creado."

#Obtener DNS del LB
DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$LB_ARN" \
  --query 'LoadBalancers[0].DNSName' \
  --output text)
echo "Load Balancer disponible en: $DNS"
