---
name: ue-cook
description: Cook an Unreal project's content with BuildCookRun (build + cook, no stage/package) for Win64, Linux or Wasm and Game/Client/Server targets - optional incremental (-iterate) cook and a map list - and report the cooked size, cook errors and warnings from the log. Use when asked to cook, to check that content cooks, to find cook errors before packaging, or to refresh cooked content quickly.
---

# Cook an Unreal project

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/cook.ps1" -ProjectPath "<project>" [-Target Game|Client|Server] [-Platform Win64|Linux|Wasm] [-Configuration Development|Shipping|DebugGame|Test] [-Maps "/Game/A+/Game/B"] [-Iterative] [-SkipBuild] [-WhatIf]
```

Talk to the user in their language. The same BuildCookRun line as `devops_ue\cook\cook_game.bat` / `cook_client.bat` /
`cook_server.bat` (`-build -cook -skippackage`, plus `-skipstage`), with timing, log parsing and a report. Packaging
the result is `ue-package`; uploading is `ue-web-deploy`.

* Engine: `devops_data\config.bat` `EnginePath`, else the `.uproject` association; `-EnginePath` overrides.
* A C++ project is built first (`-build`; `-SkipBuild` when the binaries are current). Builds and cooks take minutes
  to hours: **run it in the background** and report when finished. Default timeout 180 min (`-TimeoutMinutes`).
* `-Iterative` (`-iterate`): only re-cooks packages changed since the last cook - fast for repeated checks, but a clean
  cook (delete `Saved\Cooked`) is what a release needs; say so when the user cooks for shipping.
* `-Maps`: only these maps and their dependencies (`+` separated); default is the project's packaging settings.
* `Client` / `Server` need a source-built engine and `<Name>Client/Server.Target.cs`
  (`devops_ue\targets\create_*_target.bat`); the script stops with the reason otherwise.
* `-WhatIf` prints the RunUAT command without running.
* The editor must not hold the project's binaries (Live Coding) during the C++ build - the script warns when it is open.

## Report

Cooked folder (`Saved\Cooked\<Platform>`) and size, the cook summary lines, **every error line** (show them as a list:
asset path + message, the first 25), cook warnings (missing references, asset-registry), log path
(`Saved\Cook\cook_<Target>_<Platform>.log`), the `Time:` block. For a failure: open the first real error in the log
(not the final UAT "BuildCookRun failed" line), find the asset/class it names, explain the cause and propose the fix.
Common ones: a map or asset referenced but missing from the project, a plugin not enabled for the target platform
(`.uproject` `PlatformAllowList`), shader compile errors for the platform, Blueprint compile errors in a cooked asset.
