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

# Configura las variables
VM_NAME="$1"
SSH_KEY="$HOME/.ssh/id_rsa"

# Verifica si existe una clave SSH; si no, la genera
if [ ! -f "$SSH_KEY" ]; then
    log_debug "Generando una clave SSH para la autenticación sin contraseña..."
    ssh-keygen -t rsa -b 2048 -f "$SSH_KEY" -N ""
fi

# Copia la clave pública al servidor ESXi si no se ha copiado aún
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$USER@$HOST" "echo SSH autenticación exitosa" &>/dev/null; then
    log_debug "Copiando la clave pública al servidor ESXi para autenticación sin contraseña..."
    ssh-copy-id -i "${SSH_KEY}.pub" "$USER@$HOST"
fi

# Función para obtener el VMID y apagar la máquina virtual
power_off_vm() {
    # Obtiene el ID de la máquina virtual
    VM_ID=$(ssh "$USER@$HOST" "vim-cmd vmsvc/getallvms | grep -i \"$VM_NAME\" | awk '{print \$1}'")

    # Verifica si se encontró el ID de la máquina virtual
    if [ -z "$VM_ID" ]; then
        log_error "No se encontró el nombre de la VM \"$VM_NAME\" en $HOST."
        exit 1
    fi

    log_debug "ID de la máquina virtual \"$VM_NAME\": $VM_ID"

    # Intenta apagar la máquina virtual
    ssh "$USER@$HOST" "vim-cmd vmsvc/power.off $VM_ID" \
        && log_info "La máquina virtual \"$VM_NAME\" ha sido apagada." \
        || log_error "Error al intentar apagar la máquina virtual \"$VM_NAME\"."
}

# Ejecuta la función para apagar la máquina virtual
power_off_vm

