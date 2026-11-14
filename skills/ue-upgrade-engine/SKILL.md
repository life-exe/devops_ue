---
name: ue-upgrade-engine
description: Move an Unreal project to another engine version (e.g. 5.8 -> 5.9) - EngineAssociation in the .uproject, EnginePath in devops_data\config.bat, DefaultBuildSettings/IncludeOrderVersion in *.Target.cs (taken from the target engine's template), plugin checks, project files, editor build - then fix the compile errors and deprecations in code until it builds, and commit. Use when asked to upgrade, migrate, bump or switch the engine version of a project.
---

# Upgrade the engine version

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/upgrade_engine.ps1" -ProjectPath "<project>" -Version 5.9 -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/upgrade_engine.ps1" -ProjectPath "<project>" -Version 5.9 [-EnginePath <engine>] [-Clean]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/upgrade_engine.ps1" -ProjectPath "<project>" -BuildOnly
```

Talk to the user in their language. Needs the `ue-create-project` skill next to this one (engine detection).

## 1. Prepare

1. Run `ue-check-env` (`-For create`) if the environment is unknown.
2. Run `-WhatIf` with the target version and show the plan: current -> target engine, every file change, warnings
   (precompiled plugins without a build for the target, uncommitted changes, downgrade).
3. **Uncommitted changes**: recommend committing first, so the upgrade is one reviewable diff. Ask.
4. Ask whether to `-Clean` (Intermediate, Binaries, .vs, .sln) - recommended for a major/minor jump.

## 2. Upgrade

Run without `-WhatIf` (C++ build: many minutes - run in the background). It writes the `.uproject`,
`config.bat` and `*.Target.cs`, registers an unregistered source build, generates project files and builds
`<Name>Editor Win64 Development`. Logs: `<project>\Saved\UpgradeEngine\` (`build.log`, `build_errors.txt` with all
error lines and deprecation warnings). Exit code 2 = build failed. A background run killed with the session
(`[killed]`, no `Time:` block) did not build anything: run `-BuildOnly` again instead of trusting an old
`build_errors.txt`.

## 3. Fix the code (the main work)

While the build fails:
1. Read `Saved\UpgradeEngine\build_errors.txt`; group the errors by cause.
2. For each changed API look up the replacement **in the target engine's sources** (`<Engine>\Engine\Source\...`,
   `<Engine>\Engine\Plugins\...`): the header of the class, `UE_DEPRECATED(5.x, "...")` messages, the engine's
   upgrade notes. Don't guess signatures.
3. Fix the project code (keep the copyright header and `.clang-format` style), then
   `upgrade_engine.ps1 -BuildOnly` again.
Then handle the deprecation warnings the same way (ask whether to fix them now or later).
Typical: module/include moves (IWYU, `IncludeOrderVersion`), renamed/removed functions, `TObjectPtr`,
Enhanced Input, changed delegates or virtual signatures (`override` errors).

## 4. Finish

* Optionally open the editor once to check maps/blueprints load (Blueprint projects: assets upgrade on resave).
* Ask to commit; suggested message (the history style of these projects): `Bump version to <X.Y>`.
* Report: engine change, files changed, code fixes made, remaining deprecations, warnings, the `Time:` block.
