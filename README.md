# Despliegue de Node.js + Nginx con Packer (AWS y Azure)

Proyecto completo para crear imágenes automatizadas con Packer que incluyen una aplicación Node.js configurada con Nginx como proxy inverso. Soporta **AWS** y **Azure**.

## 📋 Estructura del Proyecto

```
proyecto-packer/
├── packer-template.pkr.hcl         # Template de Packer para AWS
├── packer-template-azure.pkr.hcl   # Template de Packer para Azure
├── nginx.conf                      # Configuración de Nginx
├── deploy.sh                       # Script de despliegue automático (AWS)
├── deploy-azure.sh                 # Script de despliegue automático (Azure)
├── cleanup.sh                      # Script de limpieza de recursos (AWS)
├── cleanup-azure.sh                # Script de limpieza de recursos (Azure)
├── variables.pkrvars.hcl           # Variables de configuración (AWS)
├── variables-azure.pkrvars.hcl     # Variables de configuración (Azure)
├── app/
│   ├── index.js                   # Aplicación Node.js
│   └── package.json                # Dependencias de Node.js
└── README.md                       # Este archivo
```

## 🚀 Requisitos Previos

### Para AWS:
1. **Cuenta de AWS** con acceso a la capa gratuita
2. **AWS CLI** instalado y configurado
3. **Packer** instalado (versión 1.9+)
4. **jq** instalado (para parsear JSON)

### Para Azure:
1. **Cuenta de Azure** con suscripción activa
2. **Azure CLI** instalado y configurado
3. **Packer** instalado (versión 1.9+)
4. **jq** instalado (para parsear JSON)

### Instalación de Requisitos

#### En Ubuntu/Debian:

```bash
# Instalar AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Instalar Packer
wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip
unzip packer_1.9.4_linux_amd64.zip
sudo mv packer /usr/local/bin/

# Instalar jq
sudo apt-get update
sudo apt-get install -y jq

# Verificar instalaciones
aws --version
packer version
jq --version
```

## ⚙️ Configuración Inicial

### 1. Configurar AWS CLI

```bash
aws configure
```

Ingresa tus credenciales:
- **AWS Access Key ID**: Tu access key
- **AWS Secret Access Key**: Tu secret key
- **Default region name**: `us-east-1` (o tu región preferida)
- **Default output format**: `json`

### 2. Verificar credenciales

```bash
aws sts get-caller-identity
```

## 📦 Ejercicio 1: Crear Imagen AMI con Packer

### Paso 1: Crear la estructura de archivos

```bash
mkdir -p proyecto-packer/app
cd proyecto-packer
```

### Paso 2: Crear todos los archivos del proyecto

- `packer-template.pkr.hcl`
- `nginx.conf`
- `app/server.js`
- `app/package.json`

### Paso 3: Inicializar Packer

```bash
packer init packer-template.pkr.hcl
```

### Paso 4: Validar el template

```bash
packer validate packer-template.pkr.hcl
```

### Paso 5: Construir la imagen

```bash
packer build packer-template.pkr.hcl
```

Este proceso toma aproximadamente 10-15 minutos y:
- Lanza una instancia EC2 temporal
- Instala Node.js 20.x
- Instala y configura Nginx
- Copia y configura la aplicación
- Crea un servicio systemd para la aplicación
- Genera la AMI final

### Paso 6: Lanzar una instancia manualmente

```bash
# Obtener el AMI ID del manifest.json
AMI_ID=$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d ":" -f2)

# Crear Security Group
SG_ID=$(aws ec2 create-security-group \
    --group-name nodejs-nginx-sg \
    --description "Security group para Node.js + Nginx" \
    --query 'GroupId' \
    --output text)

# Permitir tráfico HTTP y SSH
aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

# Crear Key Pair
aws ec2 create-key-pair \
    --key-name packer-nodejs-key \
    --query 'KeyMaterial' \
    --output text > packer-nodejs-key.pem

chmod 400 packer-nodejs-key.pem

# Lanzar instancia
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name packer-nodejs-key \
    --security-group-ids $SG_ID \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=NodeJS-Nginx-App}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

# Esperar que la instancia esté running
aws ec2 wait instance-running --instance-ids $INSTANCE_ID

# Obtener IP pública
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Aplicación disponible en: http://$PUBLIC_IP"
```

## 🤖 Ejercicio 2: Despliegue Completamente Automático

### Opción A: Usar el script deploy.sh

```bash
# Dar permisos de ejecución
chmod +x deploy.sh

# Ejecutar despliegue automático
./deploy.sh
```

El script realizará automáticamente:
1. ✅ Validación de credenciales AWS
2. ✅ Creación de Security Group
3. ✅ Creación de Key Pair
4. ✅ Inicialización de Packer
5. ✅ Validación del template
6. ✅ Construcción de la AMI
7. ✅ Lanzamiento de instancia EC2

Al finalizar, mostrará:
- Instance ID
- AMI ID
- IP pública de la aplicación
- Comandos para SSH y limpieza

### Opción B: Pipeline completo con un solo comando

```bash
# Despliegue completo desde cero
packer init packer-template.pkr.hcl && \
packer validate packer-template.pkr.hcl && \
packer build packer-template.pkr.hcl && \
./deploy.sh
```

## 🌐 Acceder a la Aplicación

Una vez desplegada, accede a la aplicación en tu navegador:

```
http://[IP_PUBLICA]
```

### Endpoints disponibles:

- `GET /` - Página principal

### Conectarse por SSH:

```bash
ssh -i packer-nodejs-key.pem ubuntu@[IP_PUBLICA]

# Ver logs de la aplicación
sudo journalctl -u nodejs-app -f

# Ver logs de Nginx
sudo tail -f /var/log/nginx/nodejs-app-access.log
```

## 🧹 Limpieza de Recursos

### Opción 1: Script automático

```bash
chmod +x cleanup.sh
./cleanup.sh
```

### Opción 2: Limpieza manual

```bash
# Terminar instancia
aws ec2 terminate-instances --instance-ids [INSTANCE_ID]

# Esperar terminación
aws ec2 wait instance-terminated --instance-ids [INSTANCE_ID]

# Eliminar AMI
aws ec2 deregister-image --image-id [AMI_ID]

# Eliminar snapshots
aws ec2 delete-snapshot --snapshot-id [SNAPSHOT_ID]

# Eliminar Security Group
aws ec2 delete-security-group --group-id [SG_ID]

# Eliminar Key Pair
aws ec2 delete-key-pair --key-name packer-nodejs-key
rm packer-nodejs-key.pem
```

## 📊 Verificación del Despliegue

### Comprobar que los servicios están activos:

```bash
# Conectar por SSH
ssh -i packer-nodejs-key.pem ubuntu@[IP_PUBLICA]

# Verificar Node.js
sudo systemctl status nodejs-app

# Verificar Nginx
sudo systemctl status nginx

# Probar la aplicación localmente
curl http://localhost:3000

# Probar a través de Nginx
curl http://localhost
```

## 🔧 Personalización

### Modificar la aplicación Node.js:

Edita `app/server.js` para cambiar la lógica de la aplicación.

### Cambiar la configuración de Nginx:

Edita `nginx.conf` para modificar el proxy o añadir nuevas rutas.

### Ajustar la región o tipo de instancia:

Edita las variables en `packer-template.pkr.hcl`:

```hcl
variable "aws_region" {
  default = "us-east-1"  # Cambiar aquí
}

variable "instance_type" {
  default = "t2.micro"   # Cambiar aquí
}
```

## 💰 Costos

Este proyecto está diseñado para la **capa gratuita de AWS**:

- **t2.micro**: 750 horas/mes gratis
- **AMI storage**: 30 GB gratis
- **Tráfico de red**: 1 GB salida gratis/mes

**⚠️ Importante**: Recuerda eliminar los recursos cuando termines para evitar cargos.

### La instancia no responde en el puerto 80

```bash
# Verificar Security Group
aws ec2 describe-security-groups --group-ids [SG_ID]

# Verificar que el puerto 80 está abierto
# Conectar por SSH y verificar servicios
```

### Build de Packer falla

```bash
# Ver logs detallados
PACKER_LOG=1 packer build packer-template.pkr.hcl
```

## ☁️ Despliegue en Azure

Este proyecto también soporta despliegue en **Microsoft Azure**. Sigue estos pasos:

### Requisitos para Azure

1. **Cuenta de Azure** con suscripción activa
2. **Azure CLI** instalado y configurado
3. **Packer** instalado (versión 1.9+)
4. **jq** instalado (para parsear JSON)

### Instalación de Azure CLI

```bash
# En Ubuntu/Debian
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# Verificar instalación
az --version
```

### Configuración Inicial de Azure

1. **Autenticarse en Azure:**
   ```bash
   az login
   ```

2. **Obtener información de tu suscripción:**
   ```bash
   az account show
   az account list --output table
   ```

3. **Configurar variables en `variables-azure.pkrvars.hcl`:**
   
   Necesitas crear una **Service Principal** en Azure:
   ```bash
   az ad sp create-for-rbac --name "packer-sp" --role contributor
   ```
   
   Esto te dará:
   - `appId` (client_id)
   - `password` (client_secret)
   - `tenant` (tenant_id)
   - `subscription` (subscription_id)
   
   Edita `variables-azure.pkrvars.hcl` con estos valores.

### Despliegue en Azure

#### Opción 1: Script automático (recomendado)

```bash
# Configurar variables primero
nano variables-azure.pkrvars.hcl

# Ejecutar despliegue
./deploy-azure.sh
```

#### Opción 2: Usando Makefile

```bash
# Verificar autenticación
make check-azure

# Inicializar Packer
make init-azure

# Validar template
make validate-azure

# Construir imagen
make build-azure

# Despliegue completo
make deploy-azure

# O todo en uno
make all-azure
```

#### Opción 3: Pasos manuales

```bash
# 1. Inicializar Packer
packer init packer-template-azure.pkr.hcl

# 2. Validar template
packer validate -var-file=variables-azure.pkrvars.hcl packer-template-azure.pkr.hcl

# 3. Construir imagen
packer build -var-file=variables-azure.pkrvars.hcl packer-template-azure.pkr.hcl

# 4. Crear VM desde la imagen (el script deploy-azure.sh lo hace automáticamente)
```

### Limpieza de Recursos en Azure

```bash
# Script automático
./cleanup-azure.sh

# O usando Makefile
make clean-azure

# Eliminar Resource Group completo
az group delete --name packer-resources --yes
```

### Verificar Estado en Azure

```bash
# Ver VMs activas
make status-azure

# Ver imágenes creadas
make images-azure

# O manualmente
az vm list --resource-group packer-resources --output table
az image list --resource-group packer-resources --output table
```

### Diferencias entre AWS y Azure

| Característica | AWS | Azure |
|---------------|-----|-------|
| Imagen | AMI | Managed Image |
| Instancia | EC2 Instance | Virtual Machine |
| Security Group | Security Group | Network Security Group |
| IP Pública | Elastic IP | Public IP Address |
| Key Pair | EC2 Key Pair | SSH Keys (generadas) |

### Costos en Azure

- **Standard_B1s**: Incluido en la capa gratuita (750 horas/mes)
- **Storage**: 5 GB gratis
- **Tráfico de red**: 5 GB salida gratis/mes

⚠️ **Importante**: Recuerda eliminar los recursos cuando termines para evitar cargos.

## 📚 Referencias

- [Documentación de Packer](https://www.packer.io/docs)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)
- [Azure CLI Reference](https://docs.microsoft.com/cli/azure/)
- [Node.js Documentation](https://nodejs.org/docs/)
- [Nginx Documentation](https://nginx.org/en/docs/)

## 🎓 Objetivos Cumplidos

✅ Automatización de instrucciones con Packer  
✅ Template funcional para Node.js + Nginx  
✅ Despliegue en **AWS** (capa gratuita)  
✅ Despliegue en **Azure** (capa gratuita)  
✅ Proceso completamente automático  
✅ Uso de IP pública  
✅ Sin intervención manual requerida  
✅ Soporte multi-cloud (AWS y Azure)
