# .dotfiles

A repository of my personal dotfiles for Windows and Linux/MacOS.

## Overview

This repository contains configuration files and installation scripts to quickly set up a consistent environment across different machines.

## Repository Structure

```
.
├── common/                  # Shared configurations (git, ignore)
├── manifests/               # Manifest files
│   ├── unix.manifest        # Configuration manifest for Unix systems
│   └── windows.manifest     # Configuration manifest for Windows systems
├── scripts/                 # Deployment and setup scripts
│   ├── bootstrap.ps1        # Full Windows setup (Apps + Dotfiles)
│   ├── deploy.ps1           # Windows dotfiles linker
│   └── deploy.sh            # Unix deployment script
├── unix/                    # Unix-specific configuration
└── windows/                 # Windows-specific configuration
```

## Quick Start

### Windows

1. **Bootstrap Environment** (Installs PowerShell 7, Winget, Git if missing)

```powershell
irm "https://tinyurl.com/mum8xazv" | iex
```

2. **Clone the repository**

   ```powershell
   git clone https://github.com/jjaroztegi/.dotfiles.git
   cd .dotfiles
   ```

3. **Deploy**

   Run with `ExecutionPolicy Bypass` to ensure the script runs regardless of system settings:

   For a full setup (Apps + Fonts + Dotfiles):

   ```powershell
   powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
   ```

   For just dotfiles linking (supports `-WhatIf` for dry-run):

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
   ```

> [!NOTE]
> **Privileges & Symlinks**: `deploy.ps1` does not automatically prompt for elevation.
>
> - To create **Symbolic Links**, you must either run the script as **Administrator** or have **Developer Mode** enabled on Windows.
> - If neither is available, the script will automatically fallback to **copying** the files instead.

> [!IMPORTANT]
> The scripts now feature **Context Preservation**. Even when elevating to Administrator, your `HOME` and `AppData` paths are preserved, ensuring dotfiles are deployed to your user profile, not the Admin's.

### Linux/macOS

1. Clone the repository

   ```bash
   git clone https://github.com/jjaroztegi/.dotfiles.git
   cd .dotfiles
   ```

2. Deploy dotfiles
   ```bash
   ./scripts/deploy.sh
   ```

## How It Works

This dotfiles manager uses a manifest-based approach to manage configuration files:

- `manifests/windows.manifest` - Configuration for Windows systems
- `manifests/unix.manifest` - Configuration for Linux/macOS systems

### Manifest Format

Each line in a manifest file has the following format:

```
source_path|operation|destination_path
```

Where:

- `source_path`: The file in the repo to be processed (relative to repo root).
- `operation`: The operation to perform (`symlink` or `copy`).
- `destination_path`: The target location on the system. Supports variables like `~`, `$HOME`, `$ProfileDir`, `$AppData`, and `$AppPath[Name]`.

Example:

```
unix/shell/.zshrc|copy|
windows/shell/Microsoft.PowerShell_profile.ps1|symlink|$ProfileDir\Microsoft.PowerShell_profile.ps1
```

## Customization

1. Fork this repository
2. Modify the manifests in `manifests/` to include your own configuration files
3. Update the deployment scripts if needed
4. Run the deployment scripts on your machines

## License

This project is under the MIT License. See [LICENSE](LICENSE) file for more details.
