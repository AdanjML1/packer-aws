packer {
  required_plugins {
    azure = {
      version = ">= 1.4.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "azure_client_id" {
  type    = string
  default = ""
}

variable "azure_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "azure_subscription_id" {
  type    = string
  default = ""
}

variable "azure_tenant_id" {
  type    = string
  default = ""
}

variable "azure_resource_group" {
  type    = string
  default = "packer-resources"
}

variable "azure_location" {
  type    = string
  default = "East US"
}

variable "azure_vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "image_name" {
  type    = string
  default = "nodejs-nginx-app"
}

source "azure-arm" "ubuntu" {
  client_id                         = var.azure_client_id
  client_secret                     = var.azure_client_secret
  subscription_id                   = var.azure_subscription_id
  tenant_id                         = var.azure_tenant_id
  
  managed_image_name                = "${var.image_name}-{{timestamp}}"
  managed_image_resource_group_name  = var.azure_resource_group
  
  os_type         = "Linux"
  image_publisher = "Canonical"
  image_offer     = "0001-com-ubuntu-server-jammy"
  image_sku       = "22_04-lts"
  
  # Usar un resource group existente para el build temporal
  # Esto evita que Packer cree y elimine resource groups temporales
  build_resource_group_name = var.azure_resource_group
  
  vm_size  = var.azure_vm_size
  
  # Configuraciones adicionales para evitar problemas
  async_resourcegroup_delete = true
  
  azure_tags = {
    Name        = "NodeJS-Nginx-App"
    Environment = "Production"
    OS          = "Ubuntu 22.04"
    CreatedBy   = "Packer"
  }
}

build {
  name = "nodejs-nginx-build-azure"
  sources = [
    "source.azure-arm.ubuntu"
  ]

  # Actualizar el sistema
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get upgrade -y"
    ]
  }

  # Instalar Node.js
  provisioner "shell" {
    inline = [
      "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -",
      "sudo apt-get install -y nodejs",
      "node --version",
      "npm --version"
    ]
  }

  # Instalar Nginx
  provisioner "shell" {
    inline = [
      "sudo apt-get install -y nginx",
      "sudo systemctl enable nginx"
    ]
  }

  # Copiar archivos de configuración
  provisioner "file" {
    source      = "app/index.js"
    destination = "/tmp/index.js"
  }

  provisioner "file" {
    source      = "app/package.json"
    destination = "/tmp/package.json"
  }

  provisioner "file" {
    source      = "nginx.conf"
    destination = "/tmp/nginx.conf"
  }

  # Configurar la aplicación
  provisioner "shell" {
    inline = [
      "sudo mkdir -p /var/www/nodejs-app",
      "sudo cp /tmp/index.js /var/www/nodejs-app/",
      "sudo cp /tmp/package.json /var/www/nodejs-app/",
      "cd /var/www/nodejs-app && sudo npm install",
      
      # Configurar Nginx
      "sudo mv /tmp/nginx.conf /etc/nginx/sites-available/nodejs-app",
      "sudo ln -sf /etc/nginx/sites-available/nodejs-app /etc/nginx/sites-enabled/",
      "sudo rm -f /etc/nginx/sites-enabled/default",
      
      # Crear servicio systemd para Node.js
      "sudo tee /etc/systemd/system/nodejs-app.service > /dev/null <<EOF",
      "[Unit]",
      "Description=Node.js Application",
      "After=network.target",
      "",
      "[Service]",
      "Type=simple",
      "User=www-data",
      "WorkingDirectory=/var/www/nodejs-app",
      "ExecStart=/usr/bin/node /var/www/nodejs-app/index.js",
      "Restart=on-failure",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      
      # Habilitar servicios
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nodejs-app",
      "sudo systemctl enable nginx"
    ]
  }

  # Limpiar y preparar para la imagen
  provisioner "shell" {
    inline = [
      "sudo apt-get clean",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*"
    ]
  }

  post-processor "manifest" {
    output = "manifest-azure.json"
    strip_path = true
  }
}

