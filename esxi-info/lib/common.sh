#!/bin/bash

# Control de errores
manage_failures() {
    set -o errexit   # Terminar si algún comando falla
    set -o nounset   # Finalizar si se utiliza una variable no definida
    set -o pipefail  # No ocultar fallos en comandos conectados por tuberías
}

# Activar trazas para depuración
activate_debug() {
    set -o xtrace   # Activar el modo de depuración para ver comandos ejecutados
}

# Variables del entorno y directorios
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="${BASE_DIR}/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_NAME="$(basename "${SCRIPT_PATH}" .sh)"
ROOT_DIR="$(cd "$(dirname "${BASE_DIR}")" && pwd)"

# Crear directorios si no existen
[[ ! -d "${ROOT_DIR}/temp" ]] && mkdir -p "${ROOT_DIR}/temp"
[[ ! -d "${ROOT_DIR}/logs" ]] && mkdir -p "${ROOT_DIR}/logs"

# Logs y archivos de bloqueo
LOCK_FILE="${ROOT_DIR}/temp/${SCRIPT_NAME}.pid"
LOG_OUT="${LOG_OUTPUT:-${ROOT_DIR}/logs/${SCRIPT_NAME}.log}"
LOG_ERR="${LOG_ERROR:-${ROOT_DIR}/logs/${SCRIPT_NAME}.error}"
IS_LOCKED=false
ERROR_LOGGED=false

# Resetear archivos de log
clear_logs() {
    > "${LOG_OUT}" || true
    > "${LOG_ERR}" || true
}

# Definición de niveles de log
readonly LVL_TRACE=0
readonly LVL_DEBUG=1
readonly LVL_INFO=2
readonly LVL_WARN=3
readonly LVL_ERROR=4
readonly LVL_CRITICAL=5
readonly LVL_OFF=6

# Función de log con formato extendido
write_log() {
    local lvl=$1; shift
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S.%N")
    local msg="$@"
    [[ "${LOG_LEVEL:-${LVL_INFO}}" -le "${lvl}" ]] && echo "${timestamp} ${USER} [${SCRIPT_NAME}][$$] ${lvl} ${msg}" || true
}

log_trace()   { write_log LVL_TRACE "$@"; }
log_debug()   { write_log LVL_DEBUG "$@"; }
log_info()    { write_log LVL_INFO "$@"; }
log_warn()    { write_log LVL_WARN "$@"; }
log_error()   { write_log LVL_ERROR "$@"; }
log_critical(){ write_log LVL_CRITICAL "$@"; }

# Manejo de salida con logs
log_and_exit() {
    local exit_status=$1; shift
    log_info "$@" && ERROR_LOGGED=true
    exit ${exit_status}
}

log_error_and_exit() {
    local exit_status=$1; shift
    log_error "$@" && ERROR_LOGGED=true
    exit ${exit_status}
}

log_critical_and_exit() {
    local exit_status=$1; shift
    log_critical "$@" && ERROR_LOGGED=true
    exit ${exit_status}
}

# Función para cargar un script adicional si está disponible
load_if_available() {
    local extra_script="$1"
    log_debug "Cargando archivo de configuración: ${extra_script}"

    if [[ -f "${extra_script}" ]]; then
        source "${extra_script}"
        return 0  # Retorna éxito si el archivo fue cargado
    else
        log_error "El archivo ${extra_script} no existe"
        return 1  # Retorna un error si el archivo no existe
    fi
}

# Manejo de finalización limpia
finish_cleanup() {
    local exit_status=$1
    local line=$2

    if [[ "${exit_status}" -ne "0" && "${ERROR_LOGGED}" != true ]]; then
        log_critical "Error ${exit_status} en la línea ${line}"
    fi

    [[ "${IS_LOCKED}" == true ]] && rm -f "${LOCK_FILE}"

    custom_cleanup

    exit ${exit_status}
}

# Función de limpieza que puede ser sobrescrita
custom_cleanup() {
    :  # No hacer nada por defecto
}

# Obtener cuerpo del correo
compose_email() {
    echo "-- LOG OUT --"
    tail -n 30 "${LOG_OUT}" 2> /dev/null || echo "No hay datos"
    echo "-- LOG ERR --"
    tail -n 30 "${LOG_ERR}" 2> /dev/null || echo "No hay datos"
}

# Obtener asunto del correo
get_subject() {
    [[ "${exit_status}" == "0" ]] && echo "Ejecución exitosa" || echo "Error detectado"
}

# Establecer bloqueo para evitar ejecuciones simultáneas
init_lock() {
    if [[ -f "${LOCK_FILE}" && -d /proc/$(cat "${LOCK_FILE}") ]]; then
        log_warn_and_exit 180 "Otra instancia está en ejecución. Abortando."
    fi
    echo $$ > "${LOCK_FILE}"
    IS_LOCKED=true
}

# Redirigir salida y errores a los logs
redirect_logs() {
    exec 1> >(tee -a "${LOG_OUT}") 2> >(tee -a "${LOG_ERR}")
}

