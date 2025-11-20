# Despliegue de Node.js + Nginx con Packer en AWS

Proyecto completo para crear imágenes AMI automatizadas con Packer que incluyen una aplicación Node.js configurada con Nginx como proxy inverso.

## 📋 Estructura del Proyecto

```
proyecto-packer/
├── packer-template.pkr.hcl    # Template principal de Packer
├── nginx.conf                  # Configuración de Nginx
├── deploy.sh                   # Script de despliegue automático
├── cleanup.sh                  # Script de limpieza de recursos
├── app/
│   ├── server.js              # Aplicación Node.js
│   └── package.json           # Dependencias de Node.js
└── README.md                   # Este archivo
```

## 🚀 Requisitos Previos

1. **Cuenta de AWS** con acceso a la capa gratuita
2. **AWS CLI** instalado y configurado
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

## 📚 Referencias

- [Documentación de Packer](https://www.packer.io/docs)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)
- [Node.js Documentation](https://nodejs.org/docs/)
- [Nginx Documentation](https://nginx.org/en/docs/)

## 🎓 Objetivos Cumplidos

✅ Automatización de instrucciones con Packer  
✅ Template funcional para Node.js + Nginx  
✅ Despliegue en AWS (capa gratuita)  
✅ Proceso completamente automático  
✅ Uso de IP pública  
✅ Sin intervención manual requerida
