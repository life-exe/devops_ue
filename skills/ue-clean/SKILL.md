---
name: ue-clean
description: Clean an Unreal project's generated files (Intermediate, Binaries, DerivedDataCache, .vs/.sln, source plugins' Intermediate/Binaries, optionally Saved, Build, Documentation and the shared engine DDC) with a size report before and the freed space after. Use when asked to clean, free disk space, remove intermediates/caches, or fix a broken build by a clean rebuild.
---

# Clean an Unreal project

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/clean.ps1" -ProjectPath "<project>" -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/clean.ps1" -ProjectPath "<project>" [-Include Saved,Build,Documentation,GlobalDDC] [-Keep DerivedDataCache,...]
```

Talk to the user in their language. Deleting is irreversible: **always run `-WhatIf` first**, show its table as
Markdown (action, item, size, note) and get a "yes".

* Default set: `Intermediate`, `Binaries`, `DerivedDataCache` (project), `.vs` + `*.sln/*.slnx`, `Intermediate`/`Binaries`
  of plugins **with sources** (precompiled plugins are never touched). `-Keep <group>` keeps any of them
  (groups: `Intermediate, Binaries, DerivedDataCache, VS, Plugins`).
* Opt-in only, ask explicitly: `Saved` (logs, autosaves, editor layout, local config), `Build` (packaged builds),
  `Documentation`, `GlobalDDC` (`%LOCALAPPDATA%\UnrealEngine\Common\DerivedDataCache` - shared by **all** projects:
  every project recompiles shaders afterwards). Zen storage is reported, never deleted.
* The script refuses to run while Unreal Editor has this project open.
* Deep paths over 260 characters are removed through `\\?\`.

## Report

The freed size, free space on the drive, warnings, the `Time:` block. For a C++ project with `Binaries`/`Intermediate`
removed: next step is `generate_project_files.bat` and an editor build (or open the `.uproject` and let it rebuild);
the first editor start recompiles shaders when the DDC was removed.
