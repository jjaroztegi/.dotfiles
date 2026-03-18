#!/usr/bin/env bash

log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*"
}

log_info() {
    log INFO "$@"
}

log_ok() {
    log OK "$@"
}

log_warn() {
    log WARN "$@"
}

log_error() {
    log ERROR "$@" >&2
}

log_dry_run() {
    log DRY-RUN "$@"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_unix_platform() {
    local kernel_name
    kernel_name="$(uname -s)"

    case "$kernel_name" in
    Darwin)
        echo macos
        ;;
    Linux)
        echo linux
        ;;
    *)
        log_error "Unsupported platform: ${kernel_name}"
        return 1
        ;;
    esac
}

run_or_print() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_dry_run "$*"
        return 0
    fi

    "$@"
}
