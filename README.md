# .dotfiles

A repository of my personal dotfiles for Windows and Linux/MacOS.

## Overview

This repository contains configuration files and installation scripts to quickly set up a consistent environment across different machines.

## Repository Structure

```
.
├── deploy.ps1                   # Windows deployment script
├── deploy.sh                    # Unix deployment script
├── MANIFEST/                    # Folder containing manifest files
│   ├── MANIFEST.unix            # Configuration manifest for Unix systems
│   └── MANIFEST.windows         # Configuration manifest for Windows systems
└── PowerShell_installer.ps1     # PowerShell installation script
```

## Quick Start

### Windows

1. Install PowerShell 7

   *(Note: The `deploy.ps1` script will not work with PowerShell 5)*
   ```powershell
   irm "https://github.com/jjaroztegi/.dotfiles/raw/main/PowerShell_installer.ps1" | iex
   ```
   Make sure to select the `CaskaydiaCove Nerd Font Mono` and to set `PowerShell 7` as default in Windows Terminal settings


2. Open PowerShell 7 and clone the repository
   ```powershell
   git clone https://github.com/jjaroztegi/.dotfiles.git
   cd .dotfiles
   ```

3. Deploy dotfiles
   ```powershell
   .\deploy.ps1
   ```

### Linux/macOS

1. Clone the repository
   ```bash
   git clone https://github.com/jjaroztegi/.dotfiles.git
   cd .dotfiles
   ```

2. Deploy dotfiles
   ```bash
   ./deploy.sh
   ```

## How It Works

This dotfiles manager uses a manifest-based approach to manage configuration files:

- `MANIFEST.windows` - Configuration for Windows systems
- `MANIFEST.unix` - Configuration for Linux/macOS systems

### Manifest Format

Each line in a manifest file has the following format:
```
filename|operation|destination
```

Where:
- `filename`: The file to be processed
- `operation`: The operation to perform (symlink, copy)
- `destination`: The destination folder/file to which the folder/file will be symlinked or copied.

Example:
```
Unix/.gitconfig|symlink|~/.gitconfig
Windows/.config|copy|
```

## Customization

1. Fork this repository
2. Modify the manifests to include your own configuration files
3. Update the deployment scripts if needed
4. Run the deployment scripts on your machines

## License

This project is under the MIT License. See [LICENSE](LICENSE) file for more details.
