# Skills

[Claude Code](https://docs.claude.com/en/docs/claude-code) skills for Unreal Engine projects.

| Skill | Description |
|-------|-------------|
| `ue-create-project` | Creates a new UE5 project (C++/Blueprint, empty MainLevel or Unreal template) wired up with devops_ue |
| `ue-web-setup` | Sets a UE 5.9+ project up for the web (Wasm): emsdk, .uproject plugin rules, Wasm settings, C++ module for BP projects, SDK check, build/package |
| `ue-web-deploy` | Installs butler / Vercel CLI / GitHub CLI and deploys a Wasm build to itch.io, Vercel or a GitHub release |

## Install

```
install_skills.bat           - asks: [G]lobal or [P]roject
install_skills.bat global    - %USERPROFILE%\.claude\skills: available in every folder
install_skills.bat project   - <project>\.claude\skills (the folder that holds devops_ue): only this project, can be committed
```

* **Project** is enough for the usual start: `mkdir MyGame`, `git init`, `git submodule add https://github.com/life-exe/devops_ue`,
  `devops_ue\skills\install_skills.bat project`, open Claude Code in `MyGame`, `/ue-create-project` creates the project in place.
* **Global** is needed to create a project in a folder that has no devops_ue yet; global skills remember the devops_ue path
  in `devops_source.txt`.
* `ue-create-project` also copies the skills into `.claude\skills\` of every project it creates.

## Usage

In Claude Code type `/ue-create-project` or just ask "create a new Unreal project".

The skill scripts can also be used without Claude:

```
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\ue_info.ps1 -Engines
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\create_project.ps1 -ProjectName MyGame -ParentDir C:\Projects -Type Cpp -EnginePath "C:\Program Files\Epic Games\UE_5.9" -Template Empty -Copyright "Copyright MyCompany. All Rights Reserved."
```
