packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "ami_name" {
  type    = string
  default = "nodejs-nginx-app"
}

source "amazon-ebs" "ubuntu" {
  ami_name      = "${var.ami_name}-{{timestamp}}"
  instance_type = var.instance_type
  region        = var.aws_region
  
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/*ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  
  ssh_username = "ubuntu"
  
  # Configuración de red
  associate_public_ip_address = true
  
  # Tags para identificar la imagen
  tags = {
    Name        = "NodeJS-Nginx-App"
    Environment = "Production"
    OS          = "Ubuntu 22.04"
    CreatedBy   = "Packer"
  }
}

build {
  name = "nodejs-nginx-build"
  sources = [
    "source.amazon-ebs.ubuntu"
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
    output = "manifest.json"
    strip_path = true
  }
}
