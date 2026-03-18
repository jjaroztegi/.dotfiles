#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/lib/unix-common.sh"
source "${REPO_ROOT}/config/unix-packages.sh"

DRY_RUN="${DRY_RUN:-false}"
PACKAGES_ONLY=false
DOTFILES_ONLY=false
MANIFEST_PATH="${DOTFILES_MANIFEST:-}"

usage() {
    cat <<'EOF'
Usage: ./scripts/bootstrap.sh [--dry-run] [--packages-only] [--dotfiles-only] [--manifest <path>]

Options:
  --dry-run           Preview actions without modifying the system.
  --packages-only     Install packages only. Skip dotfiles deployment.
  --dotfiles-only     Deploy dotfiles only. Skip package installation.
  --manifest <path>   Override the manifest path passed to deploy.sh.
  -h, --help          Show this help text.
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --packages-only)
            PACKAGES_ONLY=true
            ;;
        --dotfiles-only)
            DOTFILES_ONLY=true
            ;;
        --manifest)
            shift
            if [[ $# -eq 0 ]]; then
                log_error "--manifest requires a value."
                exit 1
            fi
            MANIFEST_PATH="$1"
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            usage >&2
            exit 1
            ;;
        esac
        shift
    done

    if [[ "$PACKAGES_ONLY" == "true" && "$DOTFILES_ONLY" == "true" ]]; then
        log_error "--packages-only and --dotfiles-only are mutually exclusive."
        exit 1
    fi
}

ensure_homebrew() {
    if command_exists brew; then
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would install Homebrew"
        return 0
    fi

    log_info "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

ensure_apt() {
    if command_exists apt-get; then
        return 0
    fi

    log_error "apt-get is required on Linux."
    exit 1
}

install_brew_packages() {
    local platform="$1"
    local taps=("${DOTFILES_BREW_TAPS[@]}")
    local formulae=("${DOTFILES_BREW_FORMULAE_COMMON[@]}")
    local casks=()

    if [[ "$platform" == "macos" ]]; then
        formulae+=("${DOTFILES_BREW_FORMULAE_MACOS[@]}")
        casks+=("${DOTFILES_BREW_CASKS_MACOS[@]}")
    fi

    if ! command_exists brew; then
        if [[ "$DRY_RUN" == "true" ]]; then
            local item
            for item in "${taps[@]}"; do
                log_dry_run "Would run: brew tap ${item}"
            done
            for item in "${formulae[@]}"; do
                log_dry_run "Would run: brew install ${item}"
            done
            for item in "${casks[@]}"; do
                log_dry_run "Would run: brew install --cask ${item}"
            done
            return 0
        fi

        log_error "brew is not available after Homebrew setup."
        exit 1
    fi

    log_info "Ensuring Homebrew packages..."
    run_or_print brew update

    local tap
    for tap in "${taps[@]}"; do
        if brew tap | grep -Fxq "$tap"; then
            log_ok "Homebrew tap already present: $tap"
        else
            run_or_print brew tap "$tap"
        fi
    done

    local formula
    for formula in "${formulae[@]}"; do
        if brew list --formula "$formula" >/dev/null 2>&1; then
            log_ok "Homebrew formula already installed: $formula"
        else
            run_or_print brew install "$formula"
        fi
    done

    local cask
    for cask in "${casks[@]}"; do
        if brew list --cask "$cask" >/dev/null 2>&1; then
            log_ok "Homebrew cask already installed: $cask"
        else
            run_or_print brew install --cask "$cask"
        fi
    done
}

apt_exec() {
    if [[ "$(id -u)" -eq 0 ]]; then
        apt-get "$@"
    else
        if ! command_exists sudo; then
            log_error "sudo is required to run apt-get as a non-root user."
            return 1
        fi
        sudo apt-get "$@"
    fi
}

install_apt_packages() {
    local packages=("${DOTFILES_APT_PACKAGES_COMMON[@]}" "${DOTFILES_APT_PACKAGES_LINUX[@]}")
    local missing_packages=()
    local package

    for package in "${packages[@]}"; do
        if dpkg -s "$package" >/dev/null 2>&1; then
            log_ok "APT package already installed: $package"
        else
            missing_packages+=("$package")
        fi
    done

    if [[ "${#missing_packages[@]}" -eq 0 ]]; then
        log_info "APT package set already satisfied."
        return 0
    fi

    log_info "Ensuring APT packages..."
    run_or_print apt_exec update
    run_or_print apt_exec install -y "${missing_packages[@]}"
}

ensure_linux_user_shims() {
    local shim_root="${HOME}/.local/bin"

    if [[ ! -d "$shim_root" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would create ${shim_root}"
        else
            mkdir -p "$shim_root"
        fi
    fi

    if command_exists fdfind && ! command_exists fd && [[ ! -e "${shim_root}/fd" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would symlink fdfind to ${shim_root}/fd"
        else
            ln -s "$(command -v fdfind)" "${shim_root}/fd"
            log_ok "Registered fd shim at ${shim_root}/fd"
        fi
    fi
}

deploy_dotfiles() {
    local deploy_args=()

    if [[ "$DRY_RUN" == "true" ]]; then
        deploy_args+=(--dry-run)
    fi

    if [[ -n "$MANIFEST_PATH" ]]; then
        deploy_args+=(--manifest "$MANIFEST_PATH")
    fi

    log_info "Deploying dotfiles..."
    bash "${SCRIPT_DIR}/deploy.sh" "${deploy_args[@]}"
}

main() {
    parse_args "$@"

    local platform
    platform="$(detect_unix_platform)"
    log_info "Detected platform: ${platform}"

    if [[ "$DOTFILES_ONLY" != "true" ]]; then
        case "$platform" in
        macos)
            ensure_homebrew
            install_brew_packages "$platform"
            ;;
        linux)
            ensure_apt
            install_apt_packages
            ensure_linux_user_shims
            ;;
        esac
    fi

    if [[ "$PACKAGES_ONLY" != "true" ]]; then
        deploy_dotfiles
    fi

    log_ok "Unix bootstrap completed."
}

main "$@"
