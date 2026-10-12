# Windows Runtime Environment Model

This repo treats Windows runtime command resolution as a persistent User environment contract. Shell profiles are allowed to improve interactive UX, but they must not be required for `node`, `npm`, `npx`, `python`, or `pip` to resolve.

## Invariant

For a given Windows user, these commands resolve consistently from:

- normal interactive PowerShell
- PowerShell over OpenSSH
- VS Code Git, Husky, and pre-commit hooks
- `pwsh -NoProfile -NonInteractive`
- coding agents and other tools launched from the user's Windows environment

Admin and non-admin users are separate Windows users. They may have different User PATH values and different runtime installations, but each user must be internally consistent.

## Environment Ownership

Persistent Machine environment:

- Contains machine-wide package manager and system tool paths only.
- Is modified only by elevated setup.
- Is not used for per-user runtime selections.

Persistent User environment:

- Owns the selected runtime command paths.
- Keeps standard Windows package-manager command surfaces available for future package installs:
  - `%LOCALAPPDATA%\Microsoft\WinGet\Links`
  - `%LOCALAPPDATA%\Microsoft\WindowsApps`
- Contains the runtime command paths, in this order, before general user shims (`<T>` is the toolchains root, see [Developer drive layout](#developer-drive-layout)):
  - `<T>\uv\bin` (uv tool entry points; only with a preferred drive)
  - `<T>\python\global-<majorMinor>\Scripts` (global venv: `python`, `pip`)
  - npm global prefix (`npm`, `npx`, `corepack`, `pnpm`, `yarn`, npm globals)
  - `<FNM_DIR>\aliases\default` (fnm's default alias junction: `node`)
  - `<T>\pnpm\bin` (only with a preferred drive)
  - `%USERPROFILE%\.local\bin`
- Ends with Git for Windows' `usr\bin` (`grep`, `sed`, `awk`, `head`, `tail`, `xargs`, `which`, `diff` for agents in PowerShell). Machine PATH still wins for `find`, `sort`, `tar`, `ssh`, and `bash`.
- Sets `PYTHONUTF8=1`.

PowerShell profile:

- Owns prompt, aliases, completion, PSReadLine, zoxide, fzf, and other interactive shell behavior.
- Must not be required to make `node`, `npm`, `npx`, `python`, or `pip` available.
- Must not define runtime command aliases or functions that change those command resolutions.

Deploy/runtime scripts:

- Install runtime managers.
- Install the selected runtime versions from `config/runtime-policy.json`.
- Persist User environment variables and PATH entries.
- Remove obsolete repo-generated runtime wrappers from `%USERPROFILE%\.local\bin`.
- Keep package-manager PATH surfaces generic so future Winget installs that publish commands through standard links work without repo changes.

## Node.js

fnm is used as an installer and default-version selector. The shell hook from `fnm env --use-on-cd` is intentionally not part of the baseline runtime contract, because GUI clients, Git hooks, `pwsh -NoProfile`, OpenSSH sessions, and agents may not load shell profiles.

The deployed baseline is:

- `FNM_DIR=<T>\fnm` (`%APPDATA%\fnm` without a preferred drive)
- `fnm install <runtime-policy node version>`
- `fnm default <runtime-policy node version>`
- User PATH includes `<FNM_DIR>\aliases\default`

That alias is a junction that `fnm default` repoints, so the PATH entry stays the same across Node versions. Never copy or recreate it as a real directory: fnm updates would stop reaching PATH and npm would write globals into it. Setup and validation fail if it is not a reparse point.

npm globals use a version-independent prefix, set with `npm config set prefix <path> --location=user` (`<T>\npm-global`, or `%APPDATA%\npm` without a preferred drive); with a preferred drive the cache is `<C>\npm`. The user `.npmrc` also holds auth tokens, so only `npm config set` touches it.

npm and corepack themselves live in that prefix (`npm install -g npm@latest corepack@latest`), and pnpm and yarn shims are written there with `corepack enable --install-directory <prefix> pnpm yarn`. The prefix precedes the fnm alias on PATH, so a Node version change neither downgrades npm to the bundled one nor removes pnpm/yarn.

With a preferred drive, `PNPM_HOME=<T>\pnpm` and `%LOCALAPPDATA%\pnpm\config\config.yaml` (pnpm 11) gets `storeDir: <drive>\.pnpm-store`, `cacheDir: <C>\pnpm`, `globalDir: <T>\pnpm\global`, `globalBinDir: <T>\pnpm\bin`; `%LOCALAPPDATA%\pnpm\config\rc` (pnpm 10) gets `store-dir`. Existing keys in both files are merged, not replaced.

Project-local `.node-version` or `.nvmrc` switching is an interactive opt-in. It can be used in a shell that evaluates `fnm env --use-on-cd`, but hooks and automation should rely on the deployed default unless a project explicitly bootstraps its own environment.

## Python

uv is the only Python manager:

- `uv python install <runtime-policy majorMinor> --default` installs the interpreter and `python.exe` trampolines into `%USERPROFILE%\.local\bin`
- `uv venv --seed --python <majorMinor> <T>\python\global-<majorMinor>` creates the global venv (`%LOCALAPPDATA%\python\global-<majorMinor>` without a preferred drive)
- The venv `Scripts` dir precedes `%USERPROFILE%\.local\bin` on the User PATH, so it is the `python`/`pip` that shells, SSH, hooks, and agents get

The Python Launcher (`py`, winget `Python.Launcher`) stays installed. System or Chocolatey Python installs must not be on the Machine PATH: Machine PATH comes first and would shadow the User entries.

## Developer drive layout

When `config/placement.json` `preferredDrive` (or `-PreferredDrive`) is set, `<T>` is `<drive>\developer\toolchains` and `<C>` is `<drive>\developer\cache`. User environment:

- `UV_CACHE_DIR=<C>\uv`, `UV_PYTHON_INSTALL_DIR=<T>\uv\python`, `UV_TOOL_DIR=<T>\uv\tools`, `UV_TOOL_BIN_DIR=<T>\uv\bin`
- `PIP_CACHE_DIR=<C>\pip`, `PLAYWRIGHT_BROWSERS_PATH=<C>\ms-playwright`, `NUGET_PACKAGES=<C>\nuget\packages`, `BUN_INSTALL_CACHE_DIR=<C>\bun`
- `GOCACHE=<C>\go-build`, `GOPATH=<drive>\developer\go`, `GOMODCACHE=<drive>\developer\go\pkg\mod`
- `CARGO_HOME=<T>\cargo`, `RUSTUP_HOME=<T>\rustup`
- `TEMP` and `TMP` = `<drive>\Temp`

Directory junctions cover tools without a relocation setting:

- `%USERPROFILE%\.cache` -> `<C>\home`
- `%USERPROFILE%\.t3\scratch` -> `<drive>\developer\.t3\scratch`

A junction is created only when the source is missing or an empty directory; otherwise setup warns and the content must be moved by hand. Use directory junctions, not file symlinks: some system services refuse file symlinks under the profile.

T3 Code worktrees use its own setting instead: when `%USERPROFILE%\.t3\userdata\settings.json` exists and has no `worktreesDirectory`, setup adds `"worktreesDirectory": "<drive>\\worktrees"`; other keys are preserved.

Without a preferred drive, tool defaults are kept; the npm prefix, fnm junction, and uv-only Python rules still apply.

## WSL

`.wslconfig` is deployed as a copy. WSL refuses to read it through a symlink ("untrusted mount point") and silently ignores it. Move distros with `wsl --manage <distro> --move <dir>` (or by setting `BasePath`), never by symlinking `ext4.vhdx`: the distro then fails to start.

## Propagation Rules

Windows gives each process an environment block at process start. Child processes inherit the parent's block unless the parent provides a different one. Updating User or Machine environment variables changes future process environments; already-running shells, VS Code windows, OpenSSH services, and agents may need restart.

Operationally:

- After bootstrap or runtime changes, restart terminals and GUI apps that need the new environment.
- Restart the `sshd` service after Machine PATH changes or before validating fresh SSH sessions.
- Restart VS Code after User PATH changes if it was already running.

References:

- [Win32 environment variables](https://learn.microsoft.com/en-us/windows/win32/procthread/environment-variables)
- [.NET Environment.SetEnvironmentVariable](https://learn.microsoft.com/en-us/dotnet/api/system.environment.setenvironmentvariable)
- [PowerShell profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles)
- [PowerShell command-line options](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh)
- [Windows OpenSSH server configuration](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration)
- [fnm README](https://github.com/Schniz/fnm)
- [uv Python versions](https://docs.astral.sh/uv/concepts/python-versions/)
- [pnpm settings](https://pnpm.io/settings)
- [Git hooks](https://git-scm.com/docs/githooks)
- [Husky startup files](https://typicode.github.io/husky/how-to.html)
- [VS Code terminal environment notes](https://code.visualstudio.com/docs/terminal/advanced)

## Validation

Run this inside the target Windows user session:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1
```

The script validates:

- current PowerShell process
- child `pwsh` with profile
- `pwsh -NoProfile -NonInteractive`
- `cmd.exe` as a Husky-like launcher
- Git `sh.exe` as a Husky-like launcher, when Git for Windows is installed

It also checks that the fnm default alias is a junction, `npm config get prefix` is outside the fnm Node install, `npm`/`npx`/`corepack`/`pnpm`/`yarn` resolve from the npm prefix, `node` from the fnm alias, `python`/`pip` from the global venv, no pyenv entry is on PATH, the expected User PATH order holds, and (with a preferred drive) `pnpm store path` is on that drive.

For SSH validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1 -SshTarget test@localhost
```

For common non-interactive SSH validation, use the named switches so PowerShell does not treat SSH options as script parameters:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1 -SshTarget test@localhost -SshBatchMode -SshDisableStrictHostKeyChecking
```

SSH output is shown but not compared to local paths by default, because SSH commonly targets another Windows user. Add `-CompareSsh` only when the SSH target is expected to use the same User environment:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1 -SshTarget test@localhost -CompareSsh
```

For admin vs non-admin validation, run the same command separately as `test` and `test_admin`. Each run should pass locally; paths do not need to match between users.

For machine-readable output:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\validate-runtime-environment.ps1 -Json
```
