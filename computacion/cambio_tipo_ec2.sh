#!/bin/bash

# --- Comprobación de parámetros ---
if [ "$#" -ne 2 ]; then
    echo "Variables: $0 <instance-id> <new-instance-type>"
    exit 1
fi

INSTANCE_ID=$1
NEW_TYPE=$2

echo "Comprobando que la instancia $INSTANCE_ID existe..."

# --- Comprobar si la instancia existe ---
INSTANCE_STATE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text 2>/dev/null)

# --- Si está en ejecución, detenerla ---
    echo "Parando la instancia $INSTANCE_ID..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null

    echo "Esperando a que la instancia se detenga..."
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
    echo "Instancia detenida."

# --- Cambiar el tipo de instancia ---
echo "Cambiando el tipo de instancia a $NEW_TYPE..."
aws ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --instance-type "{\"Value\": \"$NEW_TYPE\"}"

if [ $? -ne 0 ]; then
    echo "Error al cambiar el tipo de instancia."
    exit 1
fi
echo "Tipo de instancia cambiado correctamente a $NEW_TYPE."

# --- Arrancar la instancia ---
echo "Iniciando la instancia $INSTANCE_ID..."
aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null

echo "Esperando a que la instancia esté en ejecución..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
echo "Instancia en ejecución."

# --- Confirmación final ---
FINAL_TYPE=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].InstanceType' \
    --output text)

echo "La instancia $INSTANCE_ID ahora está ejecutándose con tipo: $FINAL_TYPE"
