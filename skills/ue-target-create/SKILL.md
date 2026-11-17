---
name: ue-target-create
description: Create Client, Server or Editor target rules (Source/<Name>Client.Target.cs, <Name>Server.Target.cs, <Name>Editor.Target.cs) for a C++ Unreal project from its own game target, so build settings and extra modules match; existing files are kept unless -Force; optionally regenerates the project files. Use when asked to add/create a dedicated server, client or editor target, or before cooking/packaging a Client/Server build.
---

# Create target rules

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/target_create.ps1" -ProjectPath "<project>" -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/target_create.ps1" -ProjectPath "<project>" [-Type Client|Server|ClientServer|Editor|All] [-Force] [-GenerateProjectFiles]
```

Talk to the user in their language. Default `-Type` is `ClientServer`. Ask which targets are needed when unclear
("dedicated server" = `Server`; a listen-server game needs only `Game`).

* The new files are copies of `Source\<Name>.Target.cs` with the class name and `TargetType` replaced, so
  `DefaultBuildSettings`, `IncludeOrderVersion` and `ExtraModuleNames` match the project. The fallback is
  `devops_ue\targets\GameModule.Target.cs.template`.
* Existing files are kept (listed as "exists, kept"); `-Force` overwrites them, so run `-WhatIf` first and tell the
  user what would be replaced.
* Blueprint-only projects have no game module: the script stops. Add a C++ module first (`ue-web-setup` does it for
  web projects).
* Client/Server targets compile only with an engine **built from source**; with an installed (Launcher) engine the
  files are created and the script warns.

## Report

The created / kept files, warnings, the `Time:` block. Next steps: `-GenerateProjectFiles` (or
`devops_ue\misc\generate_project_files.bat`), then `ue-cook` / `ue-package` with `-Target Client|Server`.
`ue-package` also creates missing Client/Server targets by itself.
