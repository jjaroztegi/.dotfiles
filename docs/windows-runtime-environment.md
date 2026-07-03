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
- Contains pyenv-win shims before pyenv-win bin:
  - `%USERPROFILE%\.pyenv\pyenv-win\shims`
  - `%USERPROFILE%\.pyenv\pyenv-win\bin`
- Contains fnm's stable default alias directory:
  - `%APPDATA%\fnm\aliases\default`
- Contains general user command shims after runtime paths:
  - `%USERPROFILE%\.local\bin`

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

- `FNM_DIR=%APPDATA%\fnm`
- `fnm install <runtime-policy node version>`
- `fnm default <runtime-policy node version>`
- User PATH includes `%APPDATA%\fnm\aliases\default`

That alias directory is stable. When the default Node version changes, the alias target changes while the PATH entry remains the same.

Project-local `.node-version` or `.nvmrc` switching is an interactive opt-in. It can be used in a shell that evaluates `fnm env --use-on-cd`, but hooks and automation should rely on the deployed default unless a project explicitly bootstraps its own environment.

## Python

pyenv-win is used through its documented shim model:

- `PYENV`, `PYENV_ROOT`, and `PYENV_HOME` point to `%USERPROFILE%\.pyenv\pyenv-win\`
- User PATH includes `%USERPROFILE%\.pyenv\pyenv-win\shims`
- User PATH includes `%USERPROFILE%\.pyenv\pyenv-win\bin`
- `pyenv global <runtime-policy python version>`
- `pyenv rehash`

The shim directory is the public command surface for `python`, `pip`, and installed Python entry points.

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
- [pyenv-win installation](https://github.com/pyenv-win/pyenv-win/blob/master/docs/installation.md)
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
