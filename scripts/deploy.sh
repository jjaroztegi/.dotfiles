#!/usr/bin/env bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

DRY_RUN="${DRY_RUN:-false}"

resolve_path() {
    local path="$1"

    path="${path/#\~/$HOME}"
    path="${path//\$HOME/$HOME}"

    local zsh_custom_default="$HOME/.oh-my-zsh/custom"
    local zsh_custom_value="${ZSH_CUSTOM:-$zsh_custom_default}"
    path="${path//\$ZSH_CUSTOM/$zsh_custom_value}"

    echo "$path"
}

symlinkFile() {
    local source_file="$1"
    local dest_path="$2"

    local source_path="${REPO_ROOT}/${source_file}"

    if [ -z "$dest_path" ]; then
        dest_path="${HOME}/$(basename "$source_file")"
    else
        dest_path="$(resolve_path "$dest_path")"
    fi

    local display_dest="${dest_path/#$HOME/~}"

    if [ ! -e "$source_path" ]; then
        printf "[ERROR] Source does not exist: %s\n" "$source_path" >&2
        return 1
    fi

    if [ -L "$dest_path" ]; then
        local current_target
        current_target="$(readlink "$dest_path")"
        if [ "$current_target" = "$source_path" ]; then
            printf "[SKIP] Already linked: %s\n" "$display_dest"
            return 0
        else
            if [ "$DRY_RUN" = "true" ]; then
                printf "[DRY-RUN] Would backup symlink (-> %s) and link: %s -> %s\n" "$current_target" "$source_file" "$display_dest"
                return 0
            fi

            # Symlink exists but points elsewhere - backup and replace
            local backup_path="${dest_path}.bak"
            printf "[BACKUP] Symlink points elsewhere, backing up: %s\n" "${display_dest}.bak"
            rm -f "$backup_path" 2>/dev/null || true
            mv "$dest_path" "$backup_path"
        fi
    elif [ -e "$dest_path" ]; then
        if [ "$DRY_RUN" = "true" ]; then
             printf "[DRY-RUN] Would backup existing file/dir and link: %s -> %s\n" "$source_file" "$display_dest"
             return 0
        fi

        # Regular file/directory exists - backup and replace
        local backup_path="${dest_path}.bak"
        printf "[BACKUP] File exists, backing up: %s\n" "${display_dest}.bak"
        rm -rf "$backup_path" 2>/dev/null || true
        mv "$dest_path" "$backup_path"
    else
        if [ "$DRY_RUN" = "true" ]; then
            printf "[DRY-RUN] Would link: %s -> %s\n" "$source_file" "$display_dest"
            return 0
        fi
    fi

    local parent_dir
    parent_dir="$(dirname "$dest_path")"
    if ! mkdir -p "$parent_dir" 2>/dev/null; then
        printf "[ERROR] Cannot create directory: %s\n" "$parent_dir" >&2
        return 1
    fi

    if ln -s "$source_path" "$dest_path"; then
        printf "[OK] %s -> %s\n" "$source_file" "$display_dest"
        return 0
    else
        printf "[ERROR] Failed to create symlink: %s\n" "$display_dest" >&2
        return 1
    fi
}

copyFile() {
    local source_file="$1"
    local dest_path="$2"

    local source_path="${REPO_ROOT}/${source_file}"

    if [ -z "$dest_path" ]; then
        dest_path="${HOME}/$(basename "$source_file")"
    else
        dest_path="$(resolve_path "$dest_path")"
    fi

    local display_dest="${dest_path/#$HOME/~}"

    if [ ! -e "$source_path" ]; then
        printf "[ERROR] Source does not exist: %s\n" "$source_path" >&2
        return 1
    fi

    if [ -e "$dest_path" ]; then
        if [ -f "$dest_path" ] && [ -f "$source_path" ]; then
            if cmp -s "$source_path" "$dest_path"; then
                printf "[SKIP] Already up to date: %s\n" "$display_dest"
                return 0
            fi
        fi

        if [ "$DRY_RUN" = "true" ]; then
             printf "[DRY-RUN] Would backup existing and copy: %s -> %s\n" "$source_file" "$display_dest"
             return 0
        fi

        local backup_path="${dest_path}.bak"
        printf "[BACKUP] Creating backup: %s\n" "${display_dest}.bak"
        if [ -d "$dest_path" ]; then
            rm -rf "$backup_path" 2>/dev/null || true
            mv "$dest_path" "$backup_path"
        else
            mv "$dest_path" "$backup_path"
        fi
    else
        if [ "$DRY_RUN" = "true" ]; then
             printf "[DRY-RUN] Would copy: %s -> %s\n" "$source_file" "$display_dest"
             return 0
        fi
    fi

    mkdir -p "$(dirname "$dest_path")"

    if [ -d "$source_path" ]; then
        cp -r "$source_path" "$dest_path"
        printf "[OK] Directory %s -> %s\n" "$source_file" "$display_dest"
    else
        cp "$source_path" "$dest_path"
        printf "[OK] %s -> %s\n" "$source_file" "$display_dest"
    fi
}

deployManifest() {
    local manifest_file="$REPO_ROOT/$1"

    if [ ! -f "$manifest_file" ]; then
        printf "[ERROR] Manifest not found: %s\n" "$manifest_file" >&2
        exit 1
    fi

    while IFS='|' read -r filename operation destination || [ -n "$filename" ]; do
        filename="$(echo "$filename" | xargs)"
        operation="$(echo "$operation" | xargs)"
        destination="$(echo "$destination" | xargs)"

        if [[ "$filename" =~ ^#.* ]] || [ -z "$filename" ]; then
            continue
        fi

        case "$operation" in
        symlink)
            symlinkFile "$filename" "$destination"
            ;;

        copy)
            copyFile "$filename" "$destination"
            ;;

        *)
            printf "[WARNING] Unknown operation %s. Skipping...\n" "$operation"
            ;;
        esac
    done < "$manifest_file"
}

install_zsh_environment() {
    printf "\n[INFO] Checking Zsh environment...\n"

    if ! command -v zsh >/dev/null 2>&1; then
        printf "[WARN] Zsh is not installed. Please install zsh first.\n"
        return
    fi

    local omz_dir="${HOME}/.oh-my-zsh"
    if [ ! -d "$omz_dir" ]; then
        if [ "$DRY_RUN" = "true" ]; then
            printf "[DRY-RUN] Would install Oh My Zsh to %s\n" "$omz_dir"
        else
            printf "[INFO] Installing Oh My Zsh...\n"
            # Unattended install, keep zshrc so we can overwrite/link it later
            sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
        fi
    else
        printf "[SKIP] Oh My Zsh already installed\n"
    fi

    local zsh_custom="${ZSH_CUSTOM:-$omz_dir/custom}"
    local plugins_dir="$zsh_custom/plugins"

    install_plugin() {
        local plugin_name="$1"
        local plugin_repo="$2"
        local plugin_path="$plugins_dir/$plugin_name"

        if [ ! -d "$plugin_path" ]; then
             if [ "$DRY_RUN" = "true" ]; then
                printf "[DRY-RUN] Would clone %s to %s\n" "$plugin_name" "$plugin_path"
            else
                printf "[INFO] Installing plugin %s...\n" "$plugin_name"
                git clone --depth 1 "$plugin_repo" "$plugin_path"
            fi
        else
             printf "[SKIP] Plugin %s already installed\n" "$plugin_name"
        fi
    }

    install_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
    install_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting.git"
}

install_zsh_environment
deployManifest "manifests/unix.manifest"
