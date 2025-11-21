#!/bin/bash

# Script de limpieza de recursos Azure
# Elimina VMs, imágenes, network security groups, IPs públicas y resource groups creados por este proyecto

set -e

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

RESOURCE_GROUP="packer-resources-west"
VM_NAME="nodejs-nginx-vm"

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}  Limpieza de Recursos Azure${NC}"
echo -e "${YELLOW}========================================${NC}\n"

# Verificar autenticación
if ! az account show > /dev/null 2>&1; then
    echo -e "${RED}✗ Error: No estás autenticado en Azure${NC}"
    exit 1
fi

# 1. Eliminar VM
echo -e "${YELLOW}[1/4] Eliminando VM...${NC}"
if az vm show --resource-group "$RESOURCE_GROUP" --name "$VM_NAME" > /dev/null 2>&1; then
    echo "Eliminando VM: $VM_NAME"
    az vm delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --yes > /dev/null 2>&1 || true
    echo -e "${GREEN}✓ VM eliminada${NC}"
else
    echo -e "${GREEN}✓ No hay VM para eliminar${NC}"
fi
echo ""

# 2. Eliminar imágenes creadas por Packer
echo -e "${YELLOW}[2/4] Eliminando imágenes...${NC}"
IMAGES=$(az image list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[?contains(name, 'nodejs-nginx-app')].name" \
    --output tsv)

if [ ! -z "$IMAGES" ]; then
    echo "$IMAGES" | while read IMAGE_NAME; do
        if [ ! -z "$IMAGE_NAME" ]; then
            echo "Eliminando imagen: $IMAGE_NAME"
            az image delete \
                --resource-group "$RESOURCE_GROUP" \
                --name "$IMAGE_NAME" \
                --yes > /dev/null 2>&1 || true
        fi
    done
    echo -e "${GREEN}✓ Imágenes eliminadas${NC}"
else
    echo -e "${GREEN}✓ No hay imágenes para eliminar${NC}"
fi
echo ""

# 3. Eliminar recursos de red
echo -e "${YELLOW}[3/4] Eliminando recursos de red...${NC}"

# Eliminar NIC
if az network nic show --resource-group "$RESOURCE_GROUP" --name "${VM_NAME}-nic" > /dev/null 2>&1; then
    az network nic delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VM_NAME}-nic" \
        --yes > /dev/null 2>&1 || true
fi

# Eliminar IP pública
if az network public-ip show --resource-group "$RESOURCE_GROUP" --name "${VM_NAME}-ip" > /dev/null 2>&1; then
    az network public-ip delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VM_NAME}-ip" \
        --yes > /dev/null 2>&1 || true
fi

# Eliminar NSG
if az network nsg show --resource-group "$RESOURCE_GROUP" --name "${VM_NAME}-nsg" > /dev/null 2>&1; then
    az network nsg delete \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VM_NAME}-nsg" \
        --yes > /dev/null 2>&1 || true
fi

echo -e "${GREEN}✓ Recursos de red eliminados${NC}"
echo ""

# 4. Eliminar Resource Group (opcional - descomentar si quieres eliminar todo)
echo -e "${YELLOW}[4/4] Opciones de limpieza...${NC}"
echo -e "${YELLOW}¿Deseas eliminar el Resource Group completo? (esto eliminará TODO)${NC}"
echo -e "Para eliminar manualmente:"
echo -e "  ${GREEN}az group delete --name $RESOURCE_GROUP --yes${NC}"
echo ""

# Limpiar archivos locales
if [ -f "manifest-azure.json" ]; then
    rm -f manifest-azure.json
    echo -e "${GREEN}✓ manifest-azure.json eliminado localmente${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Limpieza Completada${NC}"
echo -e "${GREEN}========================================${NC}\n"
echo -e "${YELLOW}Nota:${NC} El Resource Group puede contener otros recursos."
echo -e "Si quieres eliminarlo completamente, ejecuta:"
echo -e "  ${GREEN}az group delete --name $RESOURCE_GROUP --yes${NC}\n"

