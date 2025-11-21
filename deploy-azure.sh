#!/bin/bash

# Script de despliegue automático con Packer en Azure
# Este script automatiza todo el proceso de construcción y despliegue en Azure

set -e  # Salir si hay algún error

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables
RESOURCE_GROUP="packer-resources-west"
VM_NAME="nodejs-nginx-vm"
VM_SIZE="Standard_B1ls"
LOCATION="West US 2"
IMAGE_NAME=""

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Despliegue Automático con Packer (Azure)${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# 1. Verificar credenciales de Azure
echo -e "${YELLOW}[1/6] Verificando credenciales de Azure...${NC}"
if ! az account show > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: No estás autenticado en Azure${NC}"
    echo "Ejecuta: az login"
    exit 1
fi
echo -e "${GREEN}✓ Autenticado en Azure${NC}\n"

# 2. Crear Resource Group si no existe
echo -e "${YELLOW}[2/6] Configurando Resource Group...${NC}"
if ! az group show --name "$RESOURCE_GROUP" > /dev/null 2>&1; then
    echo "Creando Resource Group..."
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" > /dev/null
    echo -e "${GREEN}✓ Resource Group creado: $RESOURCE_GROUP${NC}"
else
    echo -e "${GREEN}✓ Resource Group existente: $RESOURCE_GROUP${NC}"
fi
echo ""

# 3. Inicializar Packer
echo -e "${YELLOW}[3/6] Inicializando Packer...${NC}"
if ! packer init packer-template-azure.pkr.hcl > /dev/null 2>&1; then
    echo "Packer ya inicializado o error en la inicialización"
fi
echo -e "${GREEN}✓ Packer inicializado${NC}\n"

# 4. Validar template
echo -e "${YELLOW}[4/6] Validando template de Packer...${NC}"
if ! packer validate packer-template-azure.pkr.hcl; then
    echo -e "${RED}✗ Error: Template de Packer inválido${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Template válido${NC}\n"

# 5. Construir imagen
echo -e "${YELLOW}[5/6] Construyendo imagen (esto puede tardar 10-15 minutos)...${NC}"
if ! packer build -var-file=variables-azure.pkrvars.hcl packer-template-azure.pkr.hcl; then
    echo -e "${RED}✗ Error: Fallo en la construcción de la imagen${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Imagen construida exitosamente${NC}\n"

# 6. Obtener nombre de la imagen del manifest
if [ ! -f "manifest-azure.json" ]; then
    echo -e "${RED}✗ Error: No se encontró manifest-azure.json${NC}"
    exit 1
fi

IMAGE_NAME=$(jq -r '.builds[-1].artifact_id' manifest-azure.json | cut -d ":" -f2)
if [ -z "$IMAGE_NAME" ] || [ "$IMAGE_NAME" == "null" ]; then
    echo -e "${RED}✗ Error: No se pudo obtener el nombre de la imagen${NC}"
    exit 1
fi

echo -e "${YELLOW}[6/6] Creando VM desde la imagen...${NC}"

# Crear Network Security Group con reglas HTTP y SSH
NSG_NAME="${VM_NAME}-nsg"
if ! az network nsg show --resource-group "$RESOURCE_GROUP" --name "$NSG_NAME" > /dev/null 2>&1; then
    echo "Creando Network Security Group..."
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --location "$LOCATION" > /dev/null
    
    # Permitir HTTP
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowHTTP" \
        --priority 1000 \
        --protocol Tcp \
        --destination-port-ranges 80 \
        --access Allow > /dev/null
    
    # Permitir SSH
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowSSH" \
        --priority 1001 \
        --protocol Tcp \
        --destination-port-ranges 22 \
        --access Allow > /dev/null
    
    echo -e "${GREEN}✓ Network Security Group creado${NC}"
fi

# Crear IP pública
PUBLIC_IP_NAME="${VM_NAME}-ip"
if ! az network public-ip show --resource-group "$RESOURCE_GROUP" --name "$PUBLIC_IP_NAME" > /dev/null 2>&1; then
    echo "Creando IP pública..."
    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --allocation-method Static \
        --sku Standard > /dev/null
fi

PUBLIC_IP=$(az network public-ip show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$PUBLIC_IP_NAME" \
    --query ipAddress \
    --output tsv)

# Crear VNet y Subnet si no existen
VNET_NAME="${RESOURCE_GROUP}-vnet"
SUBNET_NAME="${RESOURCE_GROUP}-subnet"
if ! az network vnet show --resource-group "$RESOURCE_GROUP" --name "$VNET_NAME" > /dev/null 2>&1; then
    echo "Creando VNet..."
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix 10.0.0.0/16 \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix 10.0.0.0/24 > /dev/null
fi

# Crear NIC
NIC_NAME="${VM_NAME}-nic"
if ! az network nic show --resource-group "$RESOURCE_GROUP" --name "$NIC_NAME" > /dev/null 2>&1; then
    echo "Creando NIC..."
    az network nic create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --public-ip-address "$PUBLIC_IP_NAME" \
        --network-security-group "$NSG_NAME" > /dev/null
fi

# Crear VM desde la imagen
echo "Creando VM desde la imagen..."
az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --image "$IMAGE_NAME" \
    --size "$VM_SIZE" \
    --admin-username azureuser \
    --generate-ssh-keys \
    --nics "$NIC_NAME" \
    --location "$LOCATION" \
    --public-ip-sku Standard > /dev/null

echo -e "${GREEN}✓ VM creada exitosamente${NC}\n"

# Esperar unos segundos para que los servicios se inicien
echo "Esperando 30 segundos para que los servicios se inicien..."
sleep 30

# Mostrar resumen
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Despliegue Completado Exitosamente${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo -e "Image Name:    ${GREEN}$IMAGE_NAME${NC}"
echo -e "VM Name:       ${GREEN}$VM_NAME${NC}"
echo -e "IP Pública:    ${GREEN}$PUBLIC_IP${NC}"
echo -e "Resource Group: ${GREEN}$RESOURCE_GROUP${NC}"
echo ""
echo -e "${YELLOW}Aplicación disponible en:${NC}"
echo -e "  ${GREEN}http://$PUBLIC_IP${NC}\n"
echo -e "${YELLOW}Para conectarse por SSH:${NC}"
echo -e "  ${GREEN}ssh azureuser@$PUBLIC_IP${NC}\n"
echo -e "${YELLOW}Para limpiar recursos:${NC}"
echo -e "  ${GREEN}./cleanup-azure.sh${NC}\n"

