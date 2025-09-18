#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "$BASH_SOURCE[0]")" && pwd)"

resolve_path() {
    local path="$1"

    # ~ to $HOME
    path="${path/#\~/$HOME}"

    path="${path//\$HOME/$HOME}"

    # $ZSH_CUSTOM with fallback to default
    local zsh_custom_default="$HOME/.oh-my-zsh/custom"
    local zsh_custom_value="${ZSH_CUSTOM:-$zsh_custom_default}"
    path="${path//\$ZSH_CUSTOM/$zsh_custom_value}"

    echo "$path"
}

symlinkFile() {
    source_path="$SCRIPT_DIR/$1"

    if [ -n "$2" ]; then
        destination="$2"
    else
        destination="$HOME/$(basename "$1")"
    fi

    destination="$(resolve_path "$destination")"
    display_destination="${destination/#$HOME/~}"

    mkdir -p $(dirname "$destination")

    if [ -L "$destination" ]; then
        echo "[WARNING] $display_destination already symlinked"
        return
    fi

    if [ -e "$destination" ]; then
        echo "[ERROR] $display_destination exists but it's not a symlink. Please fix that manually"
        return
    fi

    ln -s "$source_path" "$destination"
    echo "[OK] $source_path -> $display_destination"
}

copyFile() {
    source_path="$SCRIPT_DIR/$1"

    if [ -n "$2" ]; then
        destination="$2"
    else
        destination="$HOME/$(basename "$1")"
    fi

    destination="$(resolve_path "$destination")"
    display_destination="${destination/#$HOME/~}"

    mkdir -p $(dirname "$destination")

    if [ -e "$destination" ]; then
        echo "[WARNING] $display_destination already exists"
        return
    fi

    if [ -d "$source_path" ]; then
        cp -r "$source_path" "$destination"
        echo "[OK] Directory $source_path -> $display_destination"
    else
        cp "$source_path" "$destination"
        echo "[OK] $source_path -> $display_destination"
    fi
}

deployManifest() {
    for row in $(cat $SCRIPT_DIR/$1); do
        if [[ "$row" =~ ^#.* ]]; then
            continue
        fi

        filename=$(echo $row | cut -d \| -f 1)
        operation=$(echo $row | cut -d \| -f 2)
        destination=$(echo $row | cut -d \| -f 3)

        case $operation in
        symlink)
            symlinkFile $filename $destination
            ;;

        copy)
            copyFile $filename $destination
            ;;

        *)
            echo "[WARNING] Unknown operation $operation. Skipping..."
            ;;
        esac
    done
}

deployManifest "Manifest/MANIFEST.unix"
