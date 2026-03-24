#!/bin/bash

################################################################################
# AWS Elastic Beanstalk BLUE Environment Launcher
# 
# Script para lanzar el entorno BLUE (versión 1.0.0)
# Sube archivos a S3, crea versión de aplicación y lanza el entorno
#
# Ref: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/using-features.CNAMESwap.html
################################################################################

set -e

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

APP_NAME="franF-app"
BLUE_ENV="franF-app-blue"
BLUE_ZIP="blue-app-ebs.zip"
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
log_info "LANZAR ENTORNO BLUE"
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
if [ ! -f "$BLUE_ZIP" ]; then
    log_error "Archivo $BLUE_ZIP no encontrado en el directorio actual"
    echo "Archivos disponibles:"
    ls -lh *.zip 2>/dev/null || log_error "No hay archivos .zip"
    exit 1
fi
log_success "Archivo encontrado: $BLUE_ZIP ($(du -h "$BLUE_ZIP" | cut -f1))"

# Verificar credenciales AWS
if ! aws sts get-caller-identity --region "$AWS_REGION" &> /dev/null; then
    log_error "No se pueden validar credenciales de AWS"
    exit 1
fi
log_success "Credenciales de AWS válidas"

# ============================================================================
# VALIDAR/CREAR BUCKET S3
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
log_info "Paso 3: Subiendo $BLUE_ZIP a S3..."

if aws s3 cp "$BLUE_ZIP" "s3://$S3_BUCKET/$BLUE_ZIP" --region "$AWS_REGION"; then
    log_success "$BLUE_ZIP subido a S3"
else
    log_error "Error al subir $BLUE_ZIP a S3"
    exit 1
fi

# ============================================================================
# CREAR/VALIDAR APLICACIÓN
# ============================================================================

log_info ""
log_info "Paso 4: Validando aplicación en Elastic Beanstalk..."

app_exists=$(aws elasticbeanstalk describe-applications \
    --application-names "$APP_NAME" \
    --region "$AWS_REGION" \
    --query 'Applications[0].ApplicationName' \
    --output text 2>/dev/null || echo "")

if [ -z "$app_exists" ] || [ "$app_exists" = "None" ]; then
    log_info "Aplicación $APP_NAME no existe. Creando..."
    if aws elasticbeanstalk create-application \
        --application-name "$APP_NAME" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Aplicación $APP_NAME creada"
    else
        log_error "Error al crear aplicación $APP_NAME"
        exit 1
    fi
else
    log_success "Aplicación $APP_NAME ya existe"
fi

# ============================================================================
# CREAR VERSIÓN DE APLICACIÓN
# ============================================================================

log_info ""
log_info "Paso 5: Creando versión 1.0.0 de aplicación..."

version_exists=$(aws elasticbeanstalk describe-application-versions \
    --application-name "$APP_NAME" \
    --version-labels "1.0.0" \
    --region "$AWS_REGION" \
    --query 'ApplicationVersions[0].VersionLabel' \
    --output text 2>/dev/null || echo "")

if [ -z "$version_exists" ] || [ "$version_exists" = "None" ]; then
    log_info "Versión 1.0.0 no existe. Creando..."
    if aws elasticbeanstalk create-application-version \
        --application-name "$APP_NAME" \
        --version-label "1.0.0" \
        --source-bundle "S3Bucket=$S3_BUCKET,S3Key=$BLUE_ZIP" \
        --description "Blue version - 1.0.0 (Node.js)" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Versión 1.0.0 creada"
    else
        log_error "Error al crear versión 1.0.0"
        exit 1
    fi
else
    log_success "Versión 1.0.0 ya existe"
fi

# ============================================================================
# CREAR/VALIDAR ENTORNO BLUE
# ============================================================================

log_info ""
log_info "Paso 6: Validando entorno BLUE..."

blue_exists=$(aws elasticbeanstalk describe-environments \
    --environment-names "$BLUE_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].EnvironmentName' \
    --output text 2>/dev/null || echo "")

if [ -z "$blue_exists" ] || [ "$blue_exists" = "None" ]; then
    log_info "Entorno BLUE no existe. Creando..."
    log_info "Esto puede tardar 10-15 minutos..."
    
    if aws elasticbeanstalk create-environment \
        --application-name "$APP_NAME" \
        --environment-name "$BLUE_ENV" \
        --cname-prefix "franefun-app-blue" \
        --version-label "1.0.0" \
        --solution-stack-name "$SOLUTION_STACK" \
        --tier Name=WebServer,Type=Standard,Version="1.0" \
        --option-settings \
            "Namespace=aws:elasticbeanstalk:environment,OptionName=ServiceRole,Value=$SERVICE_ROLE" \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=IamInstanceProfile,Value=$EC2_INSTANCE_PROFILE" \
            "Namespace=aws:autoscaling:launchconfiguration,OptionName=EC2KeyName,Value=$KEY_PAIR" \
        --region "$AWS_REGION" > /dev/null 2>&1; then
        log_success "Entorno BLUE creado, esperando a que esté listo..."
        
        if wait_for_environment "$BLUE_ENV"; then
            log_success "Entorno BLUE completamente operativo"
        else
            log_error "El entorno BLUE tardó demasiado en estar listo"
            exit 1
        fi
    else
        log_error "Error al crear entorno BLUE"
        exit 1
    fi
else
    log_success "Entorno BLUE ya existe: $BLUE_ENV"
    log_info "Verificando estado..."
    
    if ! wait_for_environment "$BLUE_ENV"; then
        log_error "El entorno BLUE no está en estado Ready"
        exit 1
    fi
fi

# ============================================================================
# OBTENER INFORMACIÓN DEL ENTORNO BLUE
# ============================================================================

log_info ""
log_info "Paso 7: Obteniendo información del entorno BLUE..."

blue_url=$(aws elasticbeanstalk describe-environments \
    --environment-names "$BLUE_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].CNAME' \
    --output text 2>/dev/null || echo "")

blue_health=$(aws elasticbeanstalk describe-environments \
    --environment-names "$BLUE_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].Health' \
    --output text 2>/dev/null || echo "")

blue_status=$(aws elasticbeanstalk describe-environments \
    --environment-names "$BLUE_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].Status' \
    --output text 2>/dev/null || echo "")

blue_version=$(aws elasticbeanstalk describe-environments \
    --environment-names "$BLUE_ENV" \
    --region "$AWS_REGION" \
    --query 'Environments[0].VersionLabel' \
    --output text 2>/dev/null || echo "")

# ============================================================================
# RESUMEN FINAL
# ============================================================================

log_info ""
log_success "=========================================="
log_success "ENTORNO BLUE LISTO"
log_success "=========================================="
log_success ""
log_success "Información del Entorno BLUE:"
log_success "  Nombre:    $BLUE_ENV"
log_success "  URL:       http://$blue_url"
log_success "  Versión:   $blue_version"
log_success "  Status:    $blue_status"
log_success "  Health:    $blue_health"
log_success ""
log_info "🌐 Accede a tu aplicación:"
log_info "    http://$blue_url"
log_info ""
log_info "Próximo paso:"
log_info "    bash update_ebs_green.sh"
log_info ""

# ============================================================================
# GUARDAR INFORMACIÓN EN ARCHIVO
# ============================================================================

cat > blue_env_info.txt << EOF
BLUE ENVIRONMENT INFORMATION
============================
Timestamp: $(date)

Environment Name: $BLUE_ENV
URL: http://$blue_url
Version: $blue_version
Status: $blue_status
Health: $blue_health
Region: $AWS_REGION
Application: $APP_NAME
EOF

log_success "Información guardada en: blue_env_info.txt"

exit 0