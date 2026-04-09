# .dotfiles

A small cross-platform dotfiles repo for Windows, macOS, and Linux.

## Quick Start

Clone the repo:

```bash
git clone https://github.com/jjaroztegi/.dotfiles.git
cd .dotfiles
```

### Windows

First-run shortcut:

```powershell
irm "https://tinyurl.com/mum8xazv" | iex
```

Or run the full bootstrap from a local clone:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1
```

Prefer another drive for placement-aware installs:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 -PreferredDrive D:
```

Deploy dotfiles only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

Notes:

- A standard-user run handles user-scoped setup.
- An admin run handles machine-wide installs and deferred packages.
- `deploy.ps1` creates symlinks when possible and falls back to copying when it cannot.

### macOS / Linux

Bootstrap packages and dotfiles:

```bash
./scripts/bootstrap.sh
```

Deploy dotfiles only:

```bash
./scripts/deploy.sh
```

Dry run:

```bash
./scripts/bootstrap.sh --dry-run
```

## How It Works

The repo is manifest-driven:

- `manifests/windows.manifest`
- `manifests/macos.manifest`
- `manifests/linux.manifest`

Each line is:

```
source_path|operation|destination_path
```

## Customization

Edit the manifests, shared config in `common/`, and OS-specific files in `windows/`, `macos/`, or `linux/`.

To refresh runtime shims on Windows:

```powershell
.\scripts\ensure-runtime-tooling.ps1 -Execute
```

## Repository Structure

```
.
├── config/
├── common/
├── linux/
├── macos/
├── manifests/
├── scripts/
│   ├── bootstrap.ps1
│   ├── bootstrap.sh
│   ├── deploy.ps1
│   ├── deploy.sh
│   └── ensure-runtime-tooling.ps1
└── windows/
```

## License

This project is under the MIT License. See [LICENSE](LICENSE) file for more details.
