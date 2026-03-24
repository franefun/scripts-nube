# Script para copiar una instancia EC2 de una región a otra

set -e  # Salir si hay algún error

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para mostrar mensajes
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Verificar número de parámetros
if [ $# -ne 3 ]; then
    log_error "Número incorrecto de parámetros"
    echo "Uso: $0 <region-origen> <instance-id> <region-destino>"
    echo "Ejemplo: $0 us-east-1 i-0123456789abcdef0 us-west-2"
    exit 1
fi

REGION_ORIGEN=$1
INSTANCE_ID=$2
REGION_DESTINO=$3

log_info "Iniciando proceso de copia de instancia..."
log_info "Región origen: $REGION_ORIGEN"
log_info "Instance ID: $INSTANCE_ID"
log_info "Región destino: $REGION_DESTINO"

# Verificar que la instancia existe
log_info "Verificando que la instancia existe..."
INSTANCE_EXISTS=$(aws ec2 describe-instances \
    --region "$REGION_ORIGEN" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || echo "None")

if [ "$INSTANCE_EXISTS" == "None" ] || [ -z "$INSTANCE_EXISTS" ]; then
    log_error "La instancia $INSTANCE_ID no existe en la región $REGION_ORIGEN"
    exit 1
fi

log_info "Instancia verificada correctamente"

# Crear nombre único para la AMI
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
AMI_NAME="ami-copia-${INSTANCE_ID}-${TIMESTAMP}"

# Crear AMI en la región origen
log_info "Creando AMI en región origen (sin detener la instancia)..."
AMI_ORIGEN=$(aws ec2 create-image \
    --region "$REGION_ORIGEN" \
    --instance-id "$INSTANCE_ID" \
    --name "$AMI_NAME" \
    --description "Copia de instancia $INSTANCE_ID creada el $TIMESTAMP" \
    --no-reboot \
    --query 'ImageId' \
    --output text)

if [ -z "$AMI_ORIGEN" ]; then
    log_error "Error al crear la AMI en región origen"
    exit 1
fi

log_info "AMI creada en origen: $AMI_ORIGEN"

# Esperar a que la AMI esté disponible en origen
log_info "Esperando a que la AMI esté disponible en origen..."
aws ec2 wait image-available \
    --region "$REGION_ORIGEN" \
    --image-ids "$AMI_ORIGEN"

log_info "AMI disponible en región origen"

# Copiar AMI a región destino
log_info "Copiando AMI a región destino..."
AMI_DESTINO=$(aws ec2 copy-image \
    --region "$REGION_DESTINO" \
    --source-region "$REGION_ORIGEN" \
    --source-image-id "$AMI_ORIGEN" \
    --name "$AMI_NAME-destino" \
    --description "Copia de $AMI_ORIGEN de $REGION_ORIGEN" \
    --query 'ImageId' \
    --output text)

if [ -z "$AMI_DESTINO" ]; then
    log_error "Error al copiar la AMI a región destino"
    # Limpiar AMI origen
    aws ec2 deregister-image --region "$REGION_ORIGEN" --image-id "$AMI_ORIGEN"
    exit 1
fi

log_info "AMI copiada a destino: $AMI_DESTINO"

# Esperar a que la AMI esté disponible en destino
log_info "Esperando a que la AMI esté disponible en destino (esto puede tardar varios minutos)..."
aws ec2 wait image-available \
    --region "$REGION_DESTINO" \
    --image-ids "$AMI_DESTINO"

log_info "AMI disponible en región destino"

# Crear par de claves en región destino
KEYPAIR_NAME="keypair-${INSTANCE_ID}-${TIMESTAMP}"
KEYPAIR_FILE="${KEYPAIR_NAME}.pem"

log_info "Creando par de claves en región destino: $KEYPAIR_NAME"
aws ec2 create-key-pair \
    --region "$REGION_DESTINO" \
    --key-name "$KEYPAIR_NAME" \
    --query 'KeyMaterial' \
    --output text > "$KEYPAIR_FILE"

chmod 400 "$KEYPAIR_FILE"
log_info "Par de claves creado y guardado en: $KEYPAIR_FILE"

# Obtener VPC por defecto en región destino
log_info "Obteniendo VPC por defecto en región destino..."
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --region "$REGION_DESTINO" \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$DEFAULT_VPC" == "None" ] || [ -z "$DEFAULT_VPC" ]; then
    log_warning "No se encontró VPC por defecto, se usará la configuración automática"
    VPC_PARAM=""
else
    log_info "VPC por defecto: $DEFAULT_VPC"
    # Obtener subnet por defecto
    DEFAULT_SUBNET=$(aws ec2 describe-subnets \
        --region "$REGION_DESTINO" \
        --filters "Name=vpc-id,Values=$DEFAULT_VPC" "Name=default-for-az,Values=true" \
        --query 'Subnets[0].SubnetId' \
        --output text)
    
    if [ "$DEFAULT_SUBNET" != "None" ] && [ -n "$DEFAULT_SUBNET" ]; then
        log_info "Subnet por defecto: $DEFAULT_SUBNET"
        VPC_PARAM="--subnet-id $DEFAULT_SUBNET"
    else
        VPC_PARAM=""
    fi
fi

# Obtener security group por defecto
log_info "Obteniendo security group por defecto..."
DEFAULT_SG=$(aws ec2 describe-security-groups \
    --region "$REGION_DESTINO" \
    --filters "Name=group-name,Values=default" \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

if [ "$DEFAULT_SG" == "None" ] || [ -z "$DEFAULT_SG" ]; then
    log_warning "No se encontró security group por defecto"
    SG_PARAM=""
else
    log_info "Security group por defecto: $DEFAULT_SG"
    SG_PARAM="--security-group-ids $DEFAULT_SG"
fi

# Lanzar instancia en región destino
log_info "Lanzando nueva instancia en región destino..."
NEW_INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION_DESTINO" \
    --image-id "$AMI_DESTINO" \
    --instance-type t3.micro \
    --key-name "$KEYPAIR_NAME" \
    $SG_PARAM \
    $VPC_PARAM \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$NEW_INSTANCE_ID" ]; then
    log_error "Error al lanzar la instancia en región destino"
    # Limpiar recursos
    aws ec2 delete-key-pair --region "$REGION_DESTINO" --key-name "$KEYPAIR_NAME"
    aws ec2 deregister-image --region "$REGION_DESTINO" --image-id "$AMI_DESTINO"
    aws ec2 deregister-image --region "$REGION_ORIGEN" --image-id "$AMI_ORIGEN"
    exit 1
fi

log_info "Nueva instancia lanzada: $NEW_INSTANCE_ID"

# Esperar a que la instancia esté running
log_info "Esperando a que la instancia esté en estado 'running'..."
aws ec2 wait instance-running \
    --region "$REGION_DESTINO" \
    --instance-ids "$NEW_INSTANCE_ID"

log_info "Instancia en estado 'running'"

# Obtener IP pública de la nueva instancia
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION_DESTINO" \
    --instance-ids "$NEW_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

# Eliminar AMIs
log_info "Eliminando AMI en región origen..."
aws ec2 deregister-image --region "$REGION_ORIGEN" --image-id "$AMI_ORIGEN"
log_info "AMI eliminada en región origen"

log_info "Eliminando AMI en región destino..."
aws ec2 deregister-image --region "$REGION_DESTINO" --image-id "$AMI_DESTINO"
log_info "AMI eliminada en región destino"

# Resumen final
echo ""
log_info "=========================================="
log_info "PROCESO COMPLETADO EXITOSAMENTE"
log_info "=========================================="
log_info "Instancia origen: $INSTANCE_ID ($REGION_ORIGEN)"
log_info "Nueva instancia: $NEW_INSTANCE_ID ($REGION_DESTINO)"
log_info "IP pública: $PUBLIC_IP"
log_info "Archivo de clave: $KEYPAIR_FILE"
log_info "Nombre del key pair: $KEYPAIR_NAME"
echo ""
log_info "Para conectarte a la nueva instancia:"
echo "  ssh -i $KEYPAIR_FILE ec2-user@$PUBLIC_IP"
echo ""
log_info "Las AMIs han sido eliminadas en ambas regiones"
log_info "=========================================="