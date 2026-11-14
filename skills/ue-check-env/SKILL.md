---
name: ue-check-env
description: Check that this machine has everything the devops_ue skills need - Unreal Engine 5 (and its Wasm platform), Visual Studio C++, Git, Git LFS, git user, clang-format, Python (system and engine), Playwright, emscripten, winget, Node.js, npm, Vercel CLI, GitHub CLI, butler, Windows long paths, free disk space - with versions, login state and the fix for each missing item. Use before creating a project, setting up the web or deploying, or when asked to check / verify the environment, tools or prerequisites.
---

# Check the environment

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/check_env.ps1" [-For all|create|web|deploy] [-ProjectDir <dir>] [-EnginePath <engine>]
```

Read-only: it installs and changes nothing. Talk to the user in their language.

* `-For` picks what counts as **required**: `create` (ue-create-project), `web` (ue-web-setup), `deploy`
  (ue-web-deploy), `all` (default). Everything else is shown as optional.
* `-ProjectDir` - the drive to check free space on (default: current folder).
* Exit code 1 when something required is missing.

The table marks each item: `[ok]`, `[!!]` works but needs attention (not logged in, wrong emsdk version, long paths
off, little disk space), `[XX]` required and missing, `[--]` optional and missing - with the version, what it is
used for and the fix command.

* `-Report <file.md>` - also save the report as Markdown (date, machine, scope, result, the table). Use it when the
  user asks for a report/file, e.g. `-Report <project>\Saved\env_report.md`, and give the path.

## Report

* **Always show the full table** in the answer as a Markdown table (status, tool, version, required/optional,
  fix) - the shell output is collapsed in the UI, so the user does not see the script's own table.
  Keep the status marks `[ok]`/`[!!]`/`[XX]`/`[--]` and the legend line.
* Below the table: one line per problem (`[XX]` first, then `[!!]`) with its fix; say plainly when everything required is in place.
* Offer to fix, never fix silently. The `ue-install-env` skill installs every automatable missing item in one go
  (plan with `-WhatIf`, then install after a "yes"); for single items:
  * butler / Vercel CLI / GitHub CLI -> `ue-web-deploy` `install_tools.ps1 -Tools ...`;
  * emscripten, Playwright -> `ue-web-setup` (`-InstallPlaywright`);
  * other tools -> the `winget install ...` command from the Fix column (run only after the user agrees);
  * logins (`butler login`, `vercel login`, `gh auth login`) are interactive: ask the user to run them with `!`.
    Use the exact command from the Fix column: if butler is not on this session's PATH (installed after Claude Code
    started), it is `& "<full path>\butler.exe" login`; new terminals / a restarted Claude Code see it on PATH.
* Windows long paths need an elevated PowerShell - give the command, don't run it.
