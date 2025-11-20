# 🚀 Guía Rápida de Inicio

## Opción 1: Despliegue Automático Completo (Recomendado)

```bash
# 1. Clonar/crear la estructura del proyecto
mkdir proyecto-packer && cd proyecto-packer

# 2. Copiar todos los archivos proporcionados

# 3. Instalar dependencias (solo primera vez)
make install-deps

# 4. Configurar AWS (solo primera vez)
make configure

# 5. Despliegue completo automático
make deploy
```

**Tiempo estimado**: 15-20 minutos

## Opción 2: Paso a Paso

```bash
# 1. Verificar AWS
make check-aws

# 2. Inicializar Packer
make init

# 3. Validar template
make validate

# 4. Construir AMI
make build

# 5. Lanzar instancia
./deploy.sh
```

## Opción 3: Solo Crear la Imagen AMI

```bash
# Crear imagen sin desplegar
make init validate build

# Ver AMIs creadas
make amis

# Lanzar instancia manualmente después
make launch
```

## 🧹 Limpiar Todo

```bash
# Eliminar todos los recursos de AWS
make clean
```

## 📊 Comandos Útiles

```bash
# Ver estado de instancias
make status

# Ver AMIs disponibles
make amis

# Ver logs de construcción
make logs

# Probar app localmente
make test-app

# Formatear archivos HCL
make format

# Ver todos los comandos
make help
```

## 🎯 Para la Entrega de la Actividad

### Ejercicio 1: Template de Packer

```bash
# Crear y validar template
make init validate

# Construir imagen
make build

# Capturar el output y el AMI ID creado
```

**Archivos a entregar:**
- `packer-template.pkr.hcl`
- `nginx.conf`
- `app/server.js`
- `app/package.json`
- Captura del comando `packer build` exitoso
- AMI ID generado

### Ejercicio 2: Despliegue Automático

```bash
# Ejecutar despliegue completo
make deploy

# O usar el script directamente
./deploy.sh
```

**Archivos a entregar:**
- `deploy.sh`
- Captura del despliegue completo
- IP pública de la aplicación
- Captura de la aplicación funcionando en el navegador
- Logs del proceso automático

## ✅ Verificación Rápida

Después del despliegue, verifica:

```bash
# 1. Instancias activas
make status

# 2. Acceder a la aplicación
# Abrir en navegador: http://[IP_PUBLICA]

# 3. Conectar por SSH
ssh -i packer-nodejs-key.pem ubuntu@[IP_PUBLICA]

# 4. Verificar servicios dentro de la instancia
sudo systemctl status nodejs-app
sudo systemctl status nginx
```

## 🐛 Solución Rápida de Problemas

### Error en AWS CLI
```bash
# Reconfigurar
aws configure
make check-aws
```

### Error en Packer
```bash
# Ver logs detallados
PACKER_LOG=1 packer build packer-template.pkr.hcl
```

### No responde la aplicación
```bash
# Verificar Security Group
aws ec2 describe-security-groups --filters Name=group-name,Values=nodejs-nginx-sg

# Verificar servicios por SSH
ssh -i packer-nodejs-key.pem ubuntu@[IP_PUBLICA]
sudo journalctl -u nodejs-app -f
```

## 💡 Tips

1. **Siempre verifica los costos** antes de desplegar
2. **Limpia los recursos** cuando termines: `make clean`
3. **Guarda el Key Pair** en lugar seguro
4. **Documenta los AMI IDs** creados
5. **Usa tags** para identificar recursos fácilmente

## 📝 Notas Importantes

- La construcción de la AMI toma ~10-15 minutos
- Asegúrate de estar en la **capa gratuita de AWS**
- Solo necesitas ejecutar `make install-deps` y `make configure` una vez
- El despliegue automático crea todos los recursos necesarios
- No olvides ejecutar `make clean` para evitar cargos

## 🎓 Checklist Final

- [ ] AWS CLI configurado
- [ ] Packer instalado
- [ ] Template validado
- [ ] AMI creada exitosamente
- [ ] Instancia desplegada automáticamente
- [ ] Aplicación accesible desde IP pública
- [ ] Capturas de pantalla tomadas
- [ ] Recursos limpiados después de las pruebas
