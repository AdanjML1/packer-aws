#!/bin/bash

# Script de limpieza de recursos AWS
# Elimina instancias, AMIs, snapshots, security groups y key pairs creados por este proyecto

set -e

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KEY_NAME="packer-nodejs-key"
SG_NAME="nodejs-nginx-sg"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Limpieza de Recursos AWS${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Verificar credenciales
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: Credenciales AWS no configuradas${NC}"
    exit 1
fi

# 1. Terminar instancias
echo -e "${YELLOW}[1/5] Terminando instancias...${NC}"
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=NodeJS-Nginx-App" "Name=instance-state-name,Values=running,pending,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ ! -z "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Terminando instancia: $INSTANCE_ID"
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" > /dev/null 2>&1 || true
    done
    echo "Esperando que las instancias terminen..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID" 2>/dev/null || true
    done
    echo -e "${GREEN}✓ Instancias terminadas${NC}"
else
    echo -e "${GREEN}✓ No hay instancias para terminar${NC}"
fi
echo ""

# 2. Eliminar AMIs y snapshots
echo -e "${YELLOW}[2/5] Eliminando AMIs y snapshots...${NC}"
AMI_IDS=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=name,Values=nodejs-nginx-app-*" \
    --query 'Images[*].[ImageId,BlockDeviceMappings[0].Ebs.SnapshotId]' \
    --output text)

if [ ! -z "$AMI_IDS" ] && [ "$AMI_IDS" != "None" ]; then
    echo "$AMI_IDS" | while read AMI_ID SNAPSHOT_ID; do
        if [ ! -z "$AMI_ID" ] && [ "$AMI_ID" != "None" ]; then
            echo "Eliminando AMI: $AMI_ID"
            aws ec2 deregister-image --image-id "$AMI_ID" > /dev/null 2>&1 || true
        fi
        if [ ! -z "$SNAPSHOT_ID" ] && [ "$SNAPSHOT_ID" != "None" ]; then
            echo "Eliminando snapshot: $SNAPSHOT_ID"
            aws ec2 delete-snapshot --snapshot-id "$SNAPSHOT_ID" > /dev/null 2>&1 || true
        fi
    done
    echo -e "${GREEN}✓ AMIs y snapshots eliminados${NC}"
else
    echo -e "${GREEN}✓ No hay AMIs para eliminar${NC}"
fi
echo ""

# 3. Eliminar Security Group
echo -e "${YELLOW}[3/5] Eliminando Security Group...${NC}"
SG_ID=$(aws ec2 describe-security-groups \
    --group-names "$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    # Primero eliminar reglas de entrada
    aws ec2 describe-security-groups \
        --group-ids "$SG_ID" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output json > /tmp/sg-rules.json 2>/dev/null || echo "[]" > /tmp/sg-rules.json
    
    if [ -s /tmp/sg-rules.json ] && [ "$(cat /tmp/sg-rules.json)" != "[]" ]; then
        aws ec2 revoke-security-group-ingress \
            --group-id "$SG_ID" \
            --ip-permissions file:///tmp/sg-rules.json > /dev/null 2>&1 || true
    fi
    
    # Esperar un poco antes de eliminar el grupo
    sleep 2
    
    aws ec2 delete-security-group --group-id "$SG_ID" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Security Group eliminado${NC}"
    rm -f /tmp/sg-rules.json
else
    echo -e "${GREEN}✓ No hay Security Group para eliminar${NC}"
fi
echo ""

# 4. Eliminar Key Pair
echo -e "${YELLOW}[4/5] Eliminando Key Pair...${NC}"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" > /dev/null 2>&1; then
    aws ec2 delete-key-pair --key-name "$KEY_NAME" > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ Key Pair eliminado de AWS${NC}"
else
    echo -e "${GREEN}✓ Key Pair no existe en AWS${NC}"
fi

# Eliminar archivo local
if [ -f "${KEY_NAME}.pem" ]; then
    rm -f "${KEY_NAME}.pem"
    echo -e "${GREEN}✓ Archivo ${KEY_NAME}.pem eliminado localmente${NC}"
fi
echo ""

# 5. Limpiar archivos locales
echo -e "${YELLOW}[5/5] Limpiando archivos locales...${NC}"
if [ -f "manifest.json" ]; then
    rm -f manifest.json
    echo -e "${GREEN}✓ manifest.json eliminado${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Limpieza Completada${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo -e "${YELLOW}Nota:${NC} Algunos recursos pueden tardar unos minutos en eliminarse completamente."
echo -e "Verifica en la consola de AWS que todos los recursos han sido eliminados.\n"

