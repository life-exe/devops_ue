---
name: ue-plugin-create
description: Create a C++ plugin skeleton in an Unreal project's Plugins folder - .uplugin, module Build.cs, module header/source (Runtime, Developer or Editor module, optional extra Editor module, optional Content), formatted with the project's .clang-format, optionally wired into the game module's Build.cs and the project files regenerated. Use when asked to create/add/scaffold a plugin or move code into a plugin or a separate module.
---

# Create a plugin

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/plugin_create.ps1" -ProjectPath "<project>" -Name <PluginName> [-ModuleType Runtime|Developer|Editor] [-EditorModule] [-Content] [-AddToProject] [-GenerateProjectFiles] [-FriendlyName "..."] [-Description "..."] [-Category Other] [-Author "..."]
```

Talk to the user in their language. Ask (don't guess) the **name** and what the plugin is for; propose defaults for the rest:

* Module type: `Runtime` (game code - default), `Editor` (tools that must not ship), `Developer` (tools/dev-only code that
  can be present in non-shipping builds). Editor tooling next to runtime code -> `-EditorModule` adds `<Name>Editor`.
* `-Content`: the plugin owns assets (`Content\`, `CanContainContent: true`).
* `-AddToProject`: the game module depends on the plugin (adds `PublicDependencyModuleNames.Add("<Name>")` to
  `Source\<Project>\<Project>.Build.cs`). Without it the plugin still loads, but game code cannot include its headers.

## What it creates

```
Plugins\<Name>\<Name>.uplugin
Plugins\<Name>\Source\<Name>\<Name>.Build.cs
Plugins\<Name>\Source\<Name>\Public\<Name>.h        # F<Name>Module : IModuleInterface
Plugins\<Name>\Source\<Name>\Private\<Name>.cpp     # StartupModule / ShutdownModule, IMPLEMENT_MODULE
(+ Source\<Name>Editor\... and/or Content\ on request)
```

Copyright comes from `devops_data\config.bat` (`COPYRIGHT_LINE`) or `DefaultGame.ini`; `CreatedBy` from `-Author`, else
the `CompanyName` of the project settings. The script refuses to overwrite an existing plugin or to reuse the name of a
project module, validates the `.uplugin` JSON and never touches the `.uproject` (project-local plugins are enabled by
default; set `"EnabledByDefault": false` in the `.uplugin` only for optional ones).

## After creating

1. Regenerate project files (`-GenerateProjectFiles`, or `devops_ue\misc\generate_project_files.bat`) and build the editor
   target - a new module needs a compile; close the editor first (Live Coding cannot add modules).
2. Add the actual classes under `Public\` / `Private\` (exported with `<NAME>_API`, e.g. `WEAPONSYSTEM_API`); put
   plugin-only dependencies in the plugin's `Build.cs`, not in the game's.
3. A plugin that depends on another plugin lists it under `"Plugins": [{ "Name": "...", "Enabled": true }]` in the `.uplugin`.
4. Blueprint-only projects become C++ projects once a source plugin compiles: the script warns; Visual Studio C++ is
   needed (`ue-check-env`).
5. Web (Wasm) projects: the plugin's code must build for the Wasm platform - add `"PlatformAllowList"` / avoid
   Windows-only APIs; see `ue-web-setup`.

Report the created files, warnings and the exact next commands. Distributing the plugin as a build is `ue-plugin-package`.
