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

Prefer another drive for placement-aware installs (overrides `preferredDrive` in `config/placement.json`):

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\bootstrap.ps1 -PreferredDrive D:
```

With a preferred drive, developer toolchains (fnm, npm/pnpm globals, uv Python and tools, Cargo/rustup) go to `<drive>\developer\toolchains` and caches to `<drive>\developer\cache`; see [`docs/windows-runtime-environment.md`](docs/windows-runtime-environment.md#developer-drive-layout).

Deploy dotfiles only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\deploy.ps1
```

Notes:

- A standard-user run handles user-scoped setup.
- An admin run handles machine-wide installs and deferred packages.
- `deploy.ps1` creates symlinks when possible and falls back to copying when it cannot. `.wslconfig` is always copied: WSL ignores it when it is a symlink.
- Node comes from fnm; npm, corepack, pnpm, and yarn from the version-independent npm prefix; Python from uv.

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

Windows runtime command resolution is configured through persistent User environment variables and PATH entries, not through PowerShell profile startup side effects. See [`docs/windows-runtime-environment.md`](docs/windows-runtime-environment.md).

To apply the runtime policy on Windows:

```powershell
.\scripts\ensure-runtime-tooling.ps1 -Execute
```

To validate runtime command resolution across normal PowerShell, no-profile PowerShell, and Git/Husky-like launchers:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1
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
