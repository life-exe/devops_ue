---
name: ue-install-env
description: Install everything the devops_ue skills need that is missing on this machine - Git, Git LFS, git user, GitHub CLI, Node.js + npm, Vercel CLI, butler (itch.io), Python, clang-format, emscripten (emsdk, the version the engine requires) and Playwright for the engine's browser test - via winget / npm / pip / official downloads, then re-check. Use when asked to install, set up or prepare the tools / prerequisites / environment, or after ue-check-env found missing items.
---

# Install the environment

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/install_env.ps1" -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/install_env.ps1" [-Tools a,b,...] [-GitUserName "..." -GitUserEmail "..."] [-EmsdkDir C:\emsdk] [-EnginePath <engine>]
```

Talk to the user in their language. Installing changes the machine: **always plan first and get a "yes"**.

## 1. Plan

1. Run `install_env.ps1 -WhatIf`. It marks every tool `[ok]` / `[todo]` (with how it would be installed) /
   `[ask]` / `[skip]` and lists the **manual** items it never automates:
   Unreal Engine (Epic Games Launcher), the UE Wasm platform (Launcher options), Visual Studio C++
   ("Game development with C++" workload), Windows long paths (elevated PowerShell).
2. Show the plan as a table. Ask (`AskUserQuestion`, multiSelect) which `[todo]` items to install; recommend all.
   Mention costs: emsdk downloads ~1 GB to `C:\emsdk`; winget installers may show a **UAC prompt** the user must accept;
   `clang-format` goes through `pip --user` when Python exists (small), otherwise LLVM via winget (large).
3. `[ask]` Git user: ask for the name and e-mail as a normal message, pass `-GitUserName` / `-GitUserEmail`.

## 2. Install

Run with `-Tools <chosen,comma,separated>` (keys: `git, gitlfs, gituser, gh, node, vercel, butler, python,
clangformat, emsdk, playwright`). Installs run in a safe order (node before vercel, git before emsdk). emsdk and
winget installs can take minutes: run in the background and wait for the notification.

* Already installed tools are skipped, so re-running is safe.
* Nothing is logged in: after installing, the user runs `! gh auth login`, `! vercel login`, `! butler login`.
* Playwright goes into the engine Python under `Program Files`; if pip fails the script prints the exact command
  for an elevated terminal.

## 3. Report

The script ends with a re-check (the `ue-check-env` table) and the `Time:` block. Show the table as Markdown, list
what was installed, what failed and why, the manual items left, and remind the user to open a new terminal /
restart Claude Code and the editor (PATH, `WASM_EMSDK_ROOT`).
