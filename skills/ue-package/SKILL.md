---
name: ue-package
description: Package an Unreal project with BuildCookRun - Game, Client, Server or Client+Server targets for Win64 or Linux, and web (Wasm) builds, Development/Shipping/DebugGame/Test - with checks before (source-built engine for client/server, Linux toolchain, Wasm platform and emsdk, target rules created when missing) and a report after (output folder, size, executables, first errors from the log; for Wasm the site size, largest files and the engine's check_stage.py release scan). Use when asked to package, build a release, make a dedicated server, client or web/browser build. First-time web setup is ue-web-setup, uploading is ue-web-deploy.
---

# Package a project

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/package.ps1" -ProjectPath "<project>" [-Target Game|Client|Server|ClientServer] [-Platform Win64|Linux|Wasm] [-Configuration Development|Shipping|DebugGame|Test] [-Maps "/Game/A+/Game/B"] [-OutDir <dir>] [-Clean] [-WhatIf]
```

Talk to the user in their language.

## Ask (AskUserQuestion)

* **Target**: Game (default) / Dedicated Server / Client / Client + Server.
* **Configuration**: Development (testing) / Shipping (players). Wasm defaults to Shipping.
* **Platform**: Win64 (default) / Linux (needs the cross-compile toolchain and `LINUX_MULTIARCH_ROOT`) / Wasm (web).
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

## Web (Wasm)

`-Platform Wasm` runs the same BuildCookRun line as `devops_ue\package\package_wasm.bat` (`-iostore`, headless
cooker) into `Build\Wasm`. Game target only. Maps: `-Maps`, else the project's `+MapsToCook` in
`Config\DefaultGame.ini`, else `-allmaps` (which also cooks marketplace demo levels - suggest listing the game maps).

* Before: the engine must have the Wasm platform (UE 5.9+) and `WASM_EMSDK_ROOT` (or `C:\emsdk`). Missing -> the
  project was never set up for the web: run `ue-web-setup` first (emsdk, plugins, Wasm settings).
* After: `FileOpenOrder\` is moved out of the public folder to `Build\Wasm-FileOpenOrder` (engine open-order logs with
  build-machine paths), the project's page extras are added when `devops_data\web` exists (`head.html` before
  `</head>` between `project-head` markers - OpenGraph tags etc., `public\*` next to `index.html`; done by
  `devops_ue\package\web_page_extras.ps1`, the stale `index.html.br` is dropped), the site size is reported raw and as transferred with `.br`, plus the largest `.wasm/.ucas`,
  then the engine's `check_stage.py` runs (manifests, sha1s, debug files, release scan).
* A failed `check_stage.py` does not fail the package, but `ue-web-deploy` refuses the build for a public host. A
  `FINDING build-machine path` inside `.ucas/.pak` comes from asset metadata baked into the cook - e.g. a `FontFace`
  `SourceFilename` (`C:\Users\<name>\Downloads\Font.ttf`): clear it in the asset (editor Python
  `set_editor_property("source_filename", "")` + save), commit, package again. The warning about Epic's
  `F:\Perforce\Releases\4.24\...DroidSansFallback.ttf` is stock engine content and does not block.
* Next: `devops_ue\run\run_wasm.bat` to play locally, `ue-web-deploy` to upload.

## Report

Output folder(s) (`Build\Windows`, `WindowsServer`, `WindowsClient`, `Linux`, `Wasm`, ...), size, the executables to run, for
failures the first errors from `Saved\Package\<target>-<platform>-<config>.log` and the likely cause (compile error,
cook error with the asset name, missing SDK), warnings, the `Time:` block. Running a server + clients locally:
`devops_ue\run\run_server.bat`, `run_2_clients.bat`, `run_listen_server.bat`.
