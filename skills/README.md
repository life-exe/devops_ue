# Skills

[Claude Code](https://docs.claude.com/en/docs/claude-code) skills for Unreal Engine projects.

| Skill | Description |
|-------|-------------|
| `ue-create-project` | Creates a new UE5 project (C++/Blueprint, empty MainLevel or Unreal template) wired up with devops_ue |
| `ue-web-setup` | Sets a UE 5.9+ project up for the web (Wasm): emsdk, .uproject plugin rules, Wasm settings, C++ module for BP projects, SDK check, build/package |
| `ue-web-deploy` | Installs butler / Vercel CLI / GitHub CLI and deploys a Wasm build to itch.io, Vercel or a GitHub release |

## Install

* For the current user (works in any folder, needed for `ue-create-project`):

```
install_skills.bat
```

* For a single project: copy skill folders into `<project>\.claude\skills\`
  (`ue-create-project` does it automatically for the projects it creates).

## Usage

In Claude Code type `/ue-create-project` or just ask "create a new Unreal project".

The skill scripts can also be used without Claude:

```
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\ue_info.ps1 -Engines
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\create_project.ps1 -ProjectName MyGame -ParentDir C:\Projects -Type Cpp -EnginePath "C:\Program Files\Epic Games\UE_5.9" -Template Empty -Copyright "Copyright MyCompany. All Rights Reserved."
```
