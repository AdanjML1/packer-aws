# Variables de configuración para Packer
# Puedes personalizar estos valores según tus necesidades

aws_region = "us-east-1"
# Otras regiones disponibles:
# us-west-2, eu-west-1, ap-southeast-1, etc.

instance_type = "t2.micro"
# Tipos de instancia elegibles para capa gratuita:
# t2.micro (1 vCPU, 1 GB RAM)
# t3.micro (2 vCPU, 1 GB RAM) - mejor rendimiento

ami_name = "nodejs-nginx-app"
# Este nombre se usará como prefijo para la AMI
