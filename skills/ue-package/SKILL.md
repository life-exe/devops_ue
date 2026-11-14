---
name: ue-package
description: Package an Unreal project with BuildCookRun - Game, Client, Server or Client+Server targets for Win64 or Linux, Development/Shipping/DebugGame/Test - with checks before (source-built engine for client/server, Linux toolchain, target rules created when missing) and a report after (output folder, size, executables, first errors from the log). Use when asked to package, build a release, make a dedicated server or client build. Web builds go to ue-web-setup.
---

# Package a project

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/package.ps1" -ProjectPath "<project>" [-Target Game|Client|Server|ClientServer] [-Platform Win64|Linux] [-Configuration Development|Shipping|DebugGame|Test] [-Maps "/Game/A+/Game/B"] [-OutDir <dir>] [-Clean] [-WhatIf]
```

Talk to the user in their language. Web (Wasm) -> use `ue-web-setup` / `package_wasm.bat` instead.

## Ask (AskUserQuestion)

* **Target**: Game (default) / Dedicated Server / Client / Client + Server.
* **Configuration**: Development (testing) / Shipping (players).
* **Platform**: Win64 (default) / Linux (needs the cross-compile toolchain and `LINUX_MULTIARCH_ROOT`).
* Maps only if the user wants a subset (otherwise the project's packaging settings decide).

Show the `-WhatIf` plan (the exact BuildCookRun line), then run. Packaging takes minutes to an hour: run in the
background. A background command dies with the Claude Code session (output ends with `[killed]`, no `Time:` block):
then report "packaging did not finish" and never present an older folder in `Build\` as the new build (compare its
date with the run start).

## Checks the script makes

* Client/Server need an engine **built from source** (a Launcher engine has no client/server binaries) and a C++
  project - it stops with that explanation instead of a cryptic UAT error.
* Missing `Source\<Name>Client.Target.cs` / `<Name>Server.Target.cs` are created from the game target (tell the user
  to commit them).
* Linux without `LINUX_MULTIARCH_ROOT` stops with the toolchain hint.

## Report

Output folder(s) (`Build\Windows`, `WindowsServer`, `WindowsClient`, `Linux`, ...), size, the executables to run, for
failures the first errors from `Saved\Package\<target>-<platform>-<config>.log` and the likely cause (compile error,
cook error with the asset name, missing SDK), warnings, the `Time:` block. Running a server + clients locally:
`devops_ue\run\run_server.bat`, `run_2_clients.bat`, `run_listen_server.bat`.
