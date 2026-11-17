---
name: ue-plugin-package
description: Package an Unreal plugin with UAT BuildPlugin - compiles it for the chosen platforms (Win64, Linux, Wasm...) into a distributable folder, checks the result (binaries per platform, packaged .uplugin, size), optionally zips it and applies Fab strict-includes checks. Use when asked to package, build, export, zip or prepare a plugin for distribution/Fab, or to check that a plugin compiles on its own.
---

# Package a plugin

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/plugin_package.ps1" -ProjectPath "<project>" -Name <Plugin> [-TargetPlatforms Win64,Linux] [-Zip] [-StrictIncludes] [-NoHostPlatform] [-Clean] [-OutDir <dir>] [-WhatIf]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/plugin_package.ps1" -PluginFile "<path>\<Plugin>.uplugin" -EnginePath "<engine>"
```

Talk to the user in their language. Without `-Name` the script lists the project's plugins and stops: ask which one.
Creating a plugin is `ue-plugin-create`.

* Runs `RunUAT BuildPlugin -Plugin=<.uplugin> -Package=<dir> -Rocket -TargetPlatforms=A+B`. Default output
  `<project>\Build\Plugins\<Plugin>_<EngineMajor.Minor>` (one folder per engine version - plugins are built per version).
* **BuildPlugin builds against the engine alone, not the project.** A plugin that includes game headers or depends
  on the game module fails here; this is a good test that the plugin is self-contained.
* Engine: `devops_data\config.bat` `EnginePath`, else the `.uproject` association, else `-EnginePath`. Needs the
  C++ toolchain of every target platform (Linux: the cross-compile toolchain; Wasm: emsdk, see `ue-web-setup`).
* `-Clean` deletes a non-empty output folder first; `-OutDir` must be outside the plugin and the engine folders.
* Content-only plugins (no modules): `-NoHostPlatform`.
* `-StrictIncludes`: disables shared PCHs and enforces include-what-you-use - the check Fab applies; fix the
  includes it reports rather than dropping the flag when the goal is a Fab submission.
* `-Zip`: `<OutDir>.zip` with a `<Plugin>\` root folder. The engine puts build `Intermediate\` into the package; it is
  kept by default (the generated headers are there), `-ZipWithoutIntermediate` leaves it out of the zip - check the
  Fab/marketplace rules for the target before choosing.
* Takes minutes to an hour: **run it in the background**. Timeout 120 min (`-TimeoutMinutes`). Log:
  `<project>\Saved\PluginPackage\<Plugin>.log`.
* The editor can lock engine binaries: close it first (the script warns).

## Report

Output folder, size and file count, binaries found per platform (a platform without binaries is a warning - the build
silently skipped it), `EngineVersion` stamped into the packaged `.uplugin`, the zip path, errors (first 25 lines) and the
`Time:` block. On failure open the first real compiler error in the log, not UAT's final "BuildPlugin failed" line, and
explain it: missing `Build.cs` dependency modules, `<MODULE>_API` export missing, game-module include, platform-specific
API, a `.uplugin` `Modules` entry without matching source folder.

Before a release: bump `Version` / `VersionName` in the `.uplugin`, package for every supported engine version and
platform, and test the packaged folder by copying it into a clean project's `Plugins\`.
