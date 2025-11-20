#!/bin/bash

# Script de despliegue automático con Packer
# Este script automatiza todo el proceso de construcción y despliegue

set -e  # Salir si hay algún error

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables
KEY_NAME="packer-nodejs-key"
SG_NAME="nodejs-nginx-sg"
INSTANCE_TYPE="t2.micro"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Despliegue Automático con Packer${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# 1. Verificar credenciales AWS
echo -e "${YELLOW}[1/6] Verificando credenciales AWS...${NC}"
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: Credenciales AWS no configuradas${NC}"
    echo "Ejecuta: aws configure"
    exit 1
fi
echo -e "${GREEN}✓ Credenciales válidas${NC}\n"

# 2. Crear Key Pair si no existe (Packer lo necesita para SSH)
echo -e "${YELLOW}[2/6] Configurando Key Pair...${NC}"
if [ ! -f "${KEY_NAME}.pem" ]; then
    echo "Creando Key Pair..."
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo -e "${GREEN}✓ Key Pair creado: ${KEY_NAME}.pem${NC}"
else
    echo -e "${GREEN}✓ Key Pair existente: ${KEY_NAME}.pem${NC}"
fi
echo ""

# 3. Inicializar Packer
echo -e "${YELLOW}[3/6] Inicializando Packer...${NC}"
if ! packer init packer-template.pkr.hcl > /dev/null 2>&1; then
    echo "Packer ya inicializado o error en la inicialización"
fi
echo -e "${GREEN}✓ Packer inicializado${NC}\n"

# 4. Validar template
echo -e "${YELLOW}[4/6] Validando template de Packer...${NC}"
if ! packer validate packer-template.pkr.hcl; then
    echo -e "${RED}✗ Error: Template de Packer inválido${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Template válido${NC}\n"

# 5. Construir AMI
echo -e "${YELLOW}[5/6] Construyendo imagen AMI (esto puede tardar 10-15 minutos)...${NC}"
if ! packer build packer-template.pkr.hcl; then
    echo -e "${RED}✗ Error: Fallo en la construcción de la AMI${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AMI construida exitosamente${NC}\n"

# 7. Obtener AMI ID del manifest
if [ ! -f "manifest.json" ]; then
    echo -e "${RED}✗ Error: No se encontró manifest.json${NC}"
    exit 1
fi

AMI_ID=$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d ":" -f2)
if [ -z "$AMI_ID" ] || [ "$AMI_ID" == "null" ]; then
    echo -e "${RED}✗ Error: No se pudo obtener el AMI ID${NC}"
    exit 1
fi

# 6. Crear Security Group (solo cuando sea necesario para lanzar la instancia)
echo -e "${YELLOW}[6/6] Configurando Security Group y lanzando instancia...${NC}"
SG_ID=$(aws ec2 describe-security-groups \
    --group-names "$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ]; then
    echo "Creando Security Group..."
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SG_NAME" \
        --description "Security group para Node.js + Nginx" \
        --query 'GroupId' \
        --output text 2>/dev/null || echo "")
    
    if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
        # Permitir tráfico HTTP
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 80 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1 || true
        
        # Permitir tráfico SSH
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port 22 \
            --cidr 0.0.0.0/0 > /dev/null 2>&1 || true
        
        echo -e "${GREEN}✓ Security Group creado: $SG_ID${NC}"
    else
        echo -e "${YELLOW}⚠ No se pudo crear Security Group, usando el por defecto${NC}"
        SG_ID=""
    fi
else
    echo -e "${GREEN}✓ Security Group existente: $SG_ID${NC}"
fi

echo "Lanzando instancia EC2..."
if [ ! -z "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --security-group-ids "$SG_ID" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=NodeJS-Nginx-App}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
else
    # Usar Security Group por defecto si no se pudo crear uno
    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --key-name "$KEY_NAME" \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=NodeJS-Nginx-App}]" \
        --query 'Instances[0].InstanceId' \
        --output text)
fi

if [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}✗ Error: No se pudo lanzar la instancia${NC}"
    exit 1
fi

echo "Esperando que la instancia esté en estado 'running'..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Obtener IP pública
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo -e "${GREEN}✓ Instancia lanzada exitosamente${NC}\n"

# Esperar unos segundos para que los servicios se inicien
echo "Esperando 30 segundos para que los servicios se inicien..."
sleep 30

# Mostrar resumen
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Despliegue Completado Exitosamente${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo -e "AMI ID:        ${GREEN}$AMI_ID${NC}"
echo -e "Instance ID:   ${GREEN}$INSTANCE_ID${NC}"
echo -e "IP Pública:    ${GREEN}$PUBLIC_IP${NC}"
echo -e "Security Group: ${GREEN}$SG_ID${NC}"
echo ""
echo -e "${YELLOW}Aplicación disponible en:${NC}"
echo -e "  ${GREEN}http://$PUBLIC_IP${NC}\n"
echo -e "${YELLOW}Para conectarse por SSH:${NC}"
echo -e "  ${GREEN}ssh -i ${KEY_NAME}.pem ubuntu@$PUBLIC_IP${NC}\n"
echo -e "${YELLOW}Para limpiar recursos:${NC}"
echo -e "  ${GREEN}./cleanup.sh${NC}\n"
