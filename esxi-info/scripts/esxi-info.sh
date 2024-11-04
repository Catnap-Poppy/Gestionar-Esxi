#!/bin/bash

# Cargar las librerías comunes (manejo de errores, archivos de bloqueo, logs, notificaciones de correo, etc.)
__dir="$(cd "$(dirname "${BASH_SOURCE[-1]}")" && pwd)"
source "${__dir}/../lib/common.sh"

# Capturar errores y eventos de salida para garantizar una finalización limpia
trap 'finish_cleanup $? ${LINENO}' ERR EXIT  # finish_cleanup es la función que realiza la limpieza final y se encuentra en common.sh

# Cargar el archivo de configuración (verifica si se carga correctamente)
if ! load_if_available "${ROOT_DIR}/conf/esxi-definitions.conf"; then
    log_error "No se pudo cargar el archivo de configuración esxi.conf"
    exit 1
fi

# Verificar que las variables necesarias estén definidas
if [ -z "${HOST:-}" ] || [ -z "${USER:-}" ]; then
    log_error "El archivo de configuración no tiene los parámetros correctos."
    exit 1
fi

# Activar mejores prácticas en el script
manage_failures         # Activar manejo estricto de errores
redirect_logs           # Redirigir stdout y stderr a los archivos de log
init_lock               # Evitar ejecuciones concurrentes mediante archivo de bloqueo
clear_logs              # Limpiar los logs para la nueva ejecución
# activate_debug          # Activar trazas de depuración

# Conectarse al ESXi utilizando la clave pública
 
log_info "Conectando al host ESXi: $HOST..."

ssh -T "$USER@$HOST" << 'EOF'
  echo "Listando máquinas virtuales activas con su consumo de RAM y CPU:"

  # Obtener la lista de todas las máquinas virtuales activas
  esxcli vm process list | while read -r line; do
    # Solo procesar líneas que contengan 'World ID' o 'Display Name'
    if echo "$line" | grep -q "World ID"; then
      # Obtener el World ID
      world_id=$(echo $line | awk '{print $3}')
    elif echo "$line" | grep -q "Display Name"; then
      # Obtener el nombre de la VM
      vm_name=$(echo $line | awk -F ': ' '{print $2}')

      # Verificar si la VM es válida antes de continuar
      if [ -n "$vm_name" ]; then
        # Obtener el ID de la VM con vim-cmd
        vm_id=$(vim-cmd vmsvc/getallvms 2>/dev/null | grep "$vm_name" | awk '{print $1}')

        # Solo proceder si el vm_id es válido
        if [ -n "$vm_id" ]; then
          # Obtener la memoria asignada (en MB) y la memoria utilizada
          memory_max=$(vim-cmd vmsvc/get.summary "$vm_id" | grep "memorySizeMB" | awk '{print $3 " MB asignada"}')
          memory_used=$(vim-cmd vmsvc/get.summary "$vm_id" | grep "guestMemoryUsage" | awk '{print $3 " MB usada"}')

          # Obtener el consumo de CPU (uso en MHz)
          cpu_usage=$(vim-cmd vmsvc/get.summary "$vm_id" | grep "overallCpuUsage" | awk '{print $3 " MHz"}')

          # Mostrar resultados si se encuentra uso de RAM o CPU
            echo "VM: ${vm_name:-not_found}"
            echo " - World ID: ${world_id:-not_found}"
            echo " - Memoria asignada: ${memory_max:-not_found}"
            echo " - Memoria usada: ${memory_used:-not_found}"
            echo " - Consumo de CPU: ${cpu_usage:-not_found}"
            echo "-----------------------------------"
        fi
      fi
    fi
  done
EOF

