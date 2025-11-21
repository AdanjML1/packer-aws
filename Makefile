.PHONY: help init validate build deploy clean check-aws init-azure validate-azure build-azure deploy-azure clean-azure check-azure

# Colores para output
GREEN  := \033[0;32m
YELLOW := \033[1;33m
NC     := \033[0m

help: ## Muestra esta ayuda
	@echo "$(GREEN)Comandos disponibles:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-15s$(NC) %s\n", $$1, $$2}'

check-aws: ## Verifica la configuración de AWS
	@echo "$(YELLOW)Verificando credenciales AWS...$(NC)"
	@aws sts get-caller-identity
	@echo "$(GREEN)✓ Credenciales válidas$(NC)"

init: check-aws ## Inicializa Packer
	@echo "$(YELLOW)Inicializando Packer...$(NC)"
	packer init packer-template.pkr.hcl
	@echo "$(GREEN)✓ Packer inicializado$(NC)"

validate: ## Valida el template de Packer
	@echo "$(YELLOW)Validando template...$(NC)"
	packer validate packer-template.pkr.hcl
	@echo "$(GREEN)✓ Template válido$(NC)"

format: ## Formatea los archivos HCL
	@echo "$(YELLOW)Formateando archivos...$(NC)"
	packer fmt packer-template.pkr.hcl
	@echo "$(GREEN)✓ Archivos formateados$(NC)"

build: validate ## Construye la imagen AMI
	@echo "$(YELLOW)Construyendo imagen AMI...$(NC)"
	packer build packer-template.pkr.hcl
	@echo "$(GREEN)✓ Imagen construida exitosamente$(NC)"

deploy: ## Ejecuta el despliegue completo (build + lanzar instancia)
	@echo "$(YELLOW)Iniciando despliegue automático...$(NC)"
	@chmod +x deploy.sh
	./deploy.sh

quick-deploy: init validate build ## Despliegue rápido sin el script
	@echo "$(GREEN)Construcción completada. Usa 'make launch' para lanzar instancia$(NC)"

launch: ## Lanza una instancia con la última AMI creada
	@echo "$(YELLOW)Lanzando instancia...$(NC)"
	@AMI_ID=$$(jq -r '.builds[-1].artifact_id' manifest.json | cut -d ":" -f2); \
	echo "AMI ID: $$AMI_ID"; \
	aws ec2 run-instances \
		--image-id $$AMI_ID \
		--instance-type t2.micro \
		--tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=NodeJS-Nginx-App}]'

clean: ## Limpia todos los recursos de AWS
	@echo "$(YELLOW)Limpiando recursos...$(NC)"
	@chmod +x cleanup.sh
	./cleanup.sh
	@echo "$(GREEN)✓ Limpieza completada$(NC)"

status: ## Muestra el estado de las instancias
	@echo "$(YELLOW)Instancias activas:$(NC)"
	@aws ec2 describe-instances \
		--filters "Name=tag:Name,Values=NodeJS-Nginx-App" "Name=instance-state-name,Values=running,pending" \
		--query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,LaunchTime]' \
		--output table

amis: ## Lista las AMIs creadas
	@echo "$(YELLOW)AMIs disponibles:$(NC)"
	@aws ec2 describe-images \
		--owners self \
		--filters "Name=name,Values=nodejs-nginx-app-*" \
		--query 'Images[*].[ImageId,Name,CreationDate]' \
		--output table

logs: ## Muestra los logs de construcción
	@if [ -f manifest.json ]; then \
		cat manifest.json | jq .; \
	else \
		echo "$(YELLOW)No hay manifest disponible$(NC)"; \
	fi

install-deps: ## Instala las dependencias necesarias (Ubuntu/Debian)
	@echo "$(YELLOW)Instalando dependencias...$(NC)"
	@command -v aws >/dev/null 2>&1 || { \
		echo "Instalando AWS CLI..."; \
		curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"; \
		unzip awscliv2.zip; \
		sudo ./aws/install; \
		rm -rf aws awscliv2.zip; \
	}
	@command -v packer >/dev/null 2>&1 || { \
		echo "Instalando Packer..."; \
		wget https://releases.hashicorp.com/packer/1.9.4/packer_1.9.4_linux_amd64.zip; \
		unzip packer_1.9.4_linux_amd64.zip; \
		sudo mv packer /usr/local/bin/; \
		rm packer_1.9.4_linux_amd64.zip; \
	}
	@command -v jq >/dev/null 2>&1 || { \
		echo "Instalando jq..."; \
		sudo apt-get update; \
		sudo apt-get install -y jq; \
	}
	@echo "$(GREEN)✓ Dependencias instaladas$(NC)"

configure: ## Configura AWS CLI
	@echo "$(YELLOW)Configurando AWS CLI...$(NC)"
	aws configure
	@echo "$(GREEN)✓ Configuración completada$(NC)"

test-app: ## Prueba la aplicación localmente (requiere Node.js)
	@echo "$(YELLOW)Probando aplicación localmente...$(NC)"
	cd app && npm install && npm start

all: init validate build deploy ## Ejecuta todo el pipeline completo

# ============================================
# Comandos para Azure
# ============================================

check-azure: ## Verifica la configuración de Azure
	@echo "$(YELLOW)Verificando autenticación Azure...$(NC)"
	@az account show
	@echo "$(GREEN)✓ Autenticado en Azure$(NC)"

init-azure: check-azure ## Inicializa Packer para Azure
	@echo "$(YELLOW)Inicializando Packer para Azure...$(NC)"
	packer init packer-template-azure.pkr.hcl
	@echo "$(GREEN)✓ Packer inicializado$(NC)"

validate-azure: ## Valida el template de Packer para Azure
	@echo "$(YELLOW)Validando template de Azure...$(NC)"
	packer validate packer-template-azure.pkr.hcl
	@echo "$(GREEN)✓ Template válido$(NC)"

build-azure: validate-azure ## Construye la imagen en Azure
	@echo "$(YELLOW)Construyendo imagen en Azure...$(NC)"
	packer build -var-file=variables-azure.pkrvars.hcl packer-template-azure.pkr.hcl
	@echo "$(GREEN)✓ Imagen construida exitosamente$(NC)"

deploy-azure: ## Ejecuta el despliegue completo en Azure
	@echo "$(YELLOW)Iniciando despliegue automático en Azure...$(NC)"
	@chmod +x deploy-azure.sh
	./deploy-azure.sh

clean-azure: ## Limpia todos los recursos de Azure
	@echo "$(YELLOW)Limpiando recursos de Azure...$(NC)"
	@chmod +x cleanup-azure.sh
	./cleanup-azure.sh
	@echo "$(GREEN)✓ Limpieza completada$(NC)"

status-azure: ## Muestra el estado de las VMs en Azure
	@echo "$(YELLOW)VMs activas en Azure:$(NC)"
	@az vm list --resource-group packer-resources --show-details --query "[?powerState=='VM running'].[name,powerState,publicIps]" --output table

images-azure: ## Lista las imágenes creadas en Azure
	@echo "$(YELLOW)Imágenes disponibles en Azure:$(NC)"
	@az image list --resource-group packer-resources --query "[?contains(name, 'nodejs-nginx-app')].[name,location,osState]" --output table

all-azure: init-azure validate-azure build-azure deploy-azure ## Ejecuta todo el pipeline completo en Azure
