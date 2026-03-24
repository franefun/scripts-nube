#!/bin/bash

################################################################################
# AWS Elastic Beanstalk GREEN Environment Updater
# 
# Script para actualizar a la versión 1.0.1 en el entorno GREEN
# Crea/actualiza entorno GREEN y despliega la nueva versión
#
# Ref: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.CNAMESwap.html
################################################################################

set -e

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

APP_NAME="franF-app"
GREEN_ENV="franF-app-green"
GREEN_ZIP="green-app-ebs.zip"
S3_BUCKET="fran-ebs-versiones"
AWS_REGION="us-east-1"
SOLUTION_STACK="64bit Amazon Linux 2023 v6.6.8 running Node.js 22"

# Configuración de laboratorio AWS Academy
SERVICE_ROLE="LabRole"
EC2_INSTANCE_PROFILE="LabInstanceProfile"
KEY_PAIR="vockey"

# ============================================================================
# COLORES Y FUNCIONES
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

wait_for_environment() {
    local env_name=$1
    local max_attempts=120
    local attempt=0
    
    log_info "Esperando a que el entorno $env_name esté listo..."
    
    while [ $attempt -lt $max_attempts ]; do
        status=$(aws elasticbeanstalk describe-environments \
            --environment-names "$env_name" \
            --region "$AWS_REGION" \
            --query 'Environments[0].Status' \
            --output text 2>/dev/null || echo "Unknown")
        
        health=$(aws elasticbeanstalk describe-environments \
            --environment-names "$env_name" \
            --region "$AWS_REGION" \
            --query 'Environments[0].Health' \
            --output text 2>/dev/null || echo "Unknown")
        
        if [ "$status" = "Ready" ] && [ "$health" = "Green" ]; then
            log_success "Entorno $env_name está listo (Status: $status, Health: $health)"
            return 0
        fi
        
        echo -ne "  Status: $status | Health: $health (intento $((attempt + 1))/$max_attempts)\r"
        sleep 10
        ((attempt++))
    done
    
    log_error "Timeout esperando a que $env_name esté listo"
    return 1
}

# ============================================================================
# VALIDACIÓN INICIAL
# ============================================================================

log_info "=========================================="
log_info "ACTUALIZAR ENTORNO GREEN"
log_info "=========================================="
log_info ""

log_info "Paso 1: Validando requisitos previos..."

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
    log_error "AWS CLI no está instalado"
    exit 1
fi
log_success "AWS CLI instalado: $(aws --version)"

# Verificar archivo ZIP
if [ ! -f "$GREEN_ZIP" ]; then
    log_error "Archivo $GREEN_ZIP no encontrado en el directorio actual"
    echo "Archivos disponibles:"
    ls -lh *.zip 2>/dev/null || log_error "No hay archivos .zip"
    exit 1
fi
log_success "Archivo encontrado: $GREEN_ZIP ($(du -h "$GREEN_ZIP" | cut -f1))"

# Verificar credenciales AWS
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    log_error "No se pueden validar credenciales de AWS"
    exit 1
fi
log_success "Credenciales de AWS válidas"

# Verificar que BLUE existe
blue_env="FranF-app-blue"
blue_exists=$(aws elasticbeanstalk describe-environments \
    --environment-names "$blue_env" \
    --region "$AWS_REGION" \
    --query 'Environments[0].EnvironmentName' \
    --output text 2>/dev/null || echo "")

if [ -z "$blue_exists" ] || [ "$blue_exists" = "None" ]; then
    log_error "Entorno BLUE ($blue_env) no existe"
    log_error "Ejecuta primero: bash launch_ebs_blue.sh"
    exit 1
fi
log_success "Entorno BLUE ($blue_env) existe"

# ============================================================================
# VALIDAR BUCKET S3
# ============================================================================

log_info ""
log_info "Paso 2: Validando bucket S3 ($S3_BUCKET)..."

if ! aws s3api head-bucket --bucket "$S3_BUCKET" --region "$AWS_REGION" 2>/dev/null; then
    log_error "Bucket $S3_BUCKET no existe o no es accesible"
    exit 1
fi
log_success "Bucket $S3_BUCKET es accesible"

# ============================================================================
# SUBIR ARCHIVO A S3
# ============================================================================

log_info ""
log_info "Paso 3: Subiendo $GREEN_ZIP a S3..."

if aws s3 cp "$GREEN_ZIP" "s3://$S3_BUCKET/$GREEN_ZIP" --region "$AWS_REGION"; then
    log_success "$GREEN_ZIP subido a S3"
else
    log_error "Error al subir $GREEN_ZIP a S3"
    exit 1
fi

# ============================================================================
# CREAR VERSIÓN DE APLICACIÓN 1.0.1
# ============================================================================

log_info ""
log_info "Paso 4: Creando versión 1.0.1 de aplicación..."

version_exists=$(aws elasticbeanstalk describe-application-versions \
    --application-name "$APP_NAME" \
    --version-labels "1.0.1" \
    --region "$AWS_REGION" \
    --query 'ApplicationVersions[0].VersionLabel' \
    --output text 2>/dev/null || echo "")

if [ -z "$version_exists" ] || [ "$version_exists" = "None" ]; then
    log_info "Versión 1.0.1 no existe. Creando..."
    if aws elasticbeanstalk create-application-version \
        --application-name "$APP_NAME" \
        --version-label "1.0.1" \
        --source-bundle "S3Bucket=$S3_BUCKET,S3Key=$GREEN_ZIP" \
        --description "Green version - 1.0.1 (Node.js)" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Versión 1.0.1 creada"
    else
        log_error "Error al crear versión 1.0.1"
        exit 1
    fi
else
    log_success "Versión 1.0.1 ya existe"
fi

# ============================================================================
# CREAR/VALIDAR ENTORNO GREEN
# ============================================================================

log_info ""
log_info "Paso 5: Validando entorno GREEN..."

green_exists=$(aws elasticbeanstalk describe-environments \
    --environment-names "$GREEN_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].EnvironmentName' \
    --output text 2>/dev/null || echo "")

if [ -z "$green_exists" ] || [ "$green_exists" = "None" ]; then
    log_info "Entorno GREEN no existe. Creando..."
    log_info "Esto puede tardar 10-15 minutos..."
    
    if aws elasticbeanstalk create-environment \
        --application-name "$APP_NAME" \
        --environment-name "$GREEN_ENV" \
        --cname-prefix "franefun-app-green" \
        --version-label "1.0.0" \
        --solution-stack-name "$SOLUTION_STACK" \
        --tier Name=WebServer,Type=Standard,Version="1.0" \
        --option-settings \
            "Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=$SERVICE_ROLE" \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=$EC2_INSTANCE_PROFILE" \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=EC2KeyName,Value=$KEY_PAIR" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Entorno GREEN creado, esperando a que esté listo..."
        
        if wait_for_environment "$GREEN_ENV"; then
            log_success "Entorno GREEN completamente operativo"
        else
            log_error "El entorno GREEN tardó demasiado en estar listo"
            exit 1
        fi
    else
        log_error "Error al crear entorno GREEN"
        exit 1
    fi
else
    log_success "Entorno GREEN ya existe: $GREEN_ENV"
    log_info "Verificando estado..."
    
    if ! wait_for_environment "$GREEN_ENV"; then
        log_error "El entorno GREEN no está en estado Ready"
        exit 1
    fi
fi

# ============================================================================
# DESPLEGAR VERSIÓN 1.0.1 EN GREEN
# ============================================================================

log_info ""
log_info "Paso 6: Desplegando versión 1.0.1 en entorno GREEN..."
log_info "Esto puede tardar 5-10 minutos..."

if aws elasticbeanstalk update-environment \
    --environment-name "$GREEN_ENV" \
    --version-label "1.0.1" \
    --region "$AWS_REGION" > /dev/null 2>&1; then
    log_success "Comando de actualización enviado"
else
    log_error "Error al actualizar entorno GREEN"
    exit 1
fi

if wait_for_environment "$GREEN_ENV"; then
    log_success "Versión 1.0.1 desplegada en GREEN"
else
    log_error "El despliegue en GREEN tardó demasiado"
    exit 1
fi

# ============================================================================
# OBTENER INFORMACIÓN DE AMBOS ENTORNOS
# ============================================================================

log_info ""
log_info "Paso 7: Obteniendo información de los entornos..."

# BLUE
blue_url=$(aws elasticbeanstalk describe-environments \
    --environment-names "mck11-app-blue" \
    --region "$AWS_REGION" \
    --query 'Environments[0].CNAME' \
    --output text 2>/dev/null || echo "")

blue_version=$(aws elasticbeanstalk describe-environments \
    --environment-names "mck11-app-blue" \
    --region "$AWS_REGION" \
    --query 'Environments[0].VersionLabel' \
    --output text 2>/dev/null || echo "")

blue_health=$(aws elasticbeanstalk describe-environments \
    --environment-names "mck11-app-blue" \
    --region "$AWS_REGION" \
    --query 'Environments[0].Health' \
    --output text 2>/dev/null || echo "")

# GREEN
green_url=$(aws elasticbeanstalk describe-environments \
    --environment-names "$GREEN_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].CNAME' \
    --output text 2>/dev/null || echo "")

green_version=$(aws elasticbeanstalk describe-environments \
    --environment-names "$GREEN_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].VersionLabel' \
    --output text 2>/dev/null || echo "")

green_health=$(aws elasticbeanstalk describe-environments \
    --environment-names "$GREEN_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].Health' \
    --output text 2>/dev/null || echo "")

# ============================================================================
# RESUMEN FINAL
# ============================================================================

log_info ""
log_success "=========================================="
log_success "ENTORNO GREEN ACTUALIZADO"
log_success "=========================================="
log_success ""
log_success "Estado Actual:"
log_success ""
log_success "BLUE (Producción Actual):"
log_success "  URL:       http://$blue_url"
log_success "  Versión:   $blue_version"
log_success "  Health:    $blue_health"
log_success ""
log_success "GREEN (Nueva Versión):"
log_success "  URL:       http://$green_url"
log_success "  Versión:   $green_version"
log_success "  Health:    $green_health"
log_success ""
log_info "🧪 Testing GREEN (Nueva Versión v1.0.1):"
log_info "    http://$green_url"
log_info ""
log_warning "⚠️  VERIFICA QUE GREEN FUNCIONA CORRECTAMENTE ANTES DE HACER SWAP"
log_info ""
log_info "Para intercambiar el tráfico (BLUE → GREEN):"
log_info "    bash swap_ebs_environments.sh"
log_info ""

# ============================================================================
# GUARDAR INFORMACIÓN EN ARCHIVO
# ============================================================================

cat > green_env_info.txt << EOF
GREEN ENVIRONMENT INFORMATION
=============================
Timestamp: $(date)

BLUE Environment:
  Name: mck11-app-blue
  URL: http://$blue_url
  Version: $blue_version
  Health: $blue_health

GREEN Environment:
  Name: $GREEN_ENV
  URL: http://$green_url
  Version: $green_version
  Health: $green_health

Region: $AWS_REGION
Application: $APP_NAME
EOF

log_success "Información guardada en: green_env_info.txt"

exit 0