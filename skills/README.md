# Skills

[Claude Code](https://docs.claude.com/en/docs/claude-code) skills for Unreal Engine projects.

| Skill | Description |
|-------|-------------|
| `ue-check-env` | Checks the machine: UE, Visual Studio C++, Git/LFS, Python, Playwright, emsdk, Node.js, Vercel CLI, GitHub CLI, butler, long paths, disk space |
| `ue-install-env` | Installs what is missing (Git, LFS, gh, Node.js, Vercel CLI, butler, Python, clang-format, emsdk, Playwright), then re-checks |
| `ue-create-project` | Creates a new UE5 project (C++/Blueprint, empty MainLevel or Unreal template) wired up with devops_ue |
| `ue-upgrade-engine` | Moves a project to another engine version (uproject, config.bat, Target.cs), builds it, lists errors/deprecations to fix |
| `ue-run-tests` | Builds and runs automation tests headless, reports failures; coverage, JUnit, new spec/test files |
| `ue-package` | Packages Game/Client/Server for Win64/Linux and web (Wasm) builds with pre-checks and a size/exe report (Wasm: + release scan) |
| `ue-docs` | Doxygen documentation with the devops_ue themes and UE macro filter |
| `ue-clean` | Removes Intermediate/Binaries/DDC/... with a size report (Saved, Build, global DDC opt-in) |
| `ue-content-audit` | Content size by folder/type/class, largest packages, unreferenced candidates, big textures, redirectors |
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
* `install_skills.bat` ends with `check_skills.ps1`, which compares every installed copy (user and project) with
  `devops_ue\skills` by SHA256 and reports stale ones; run it any time:
  `powershell -ExecutionPolicy Bypass -File devops_ue\skills\check_skills.ps1`.
  The skill scripts also warn when the copy they run from differs from the project's `devops_ue`.

## Usage

In Claude Code type `/ue-create-project` or just ask "create a new Unreal project".

The skill scripts can also be used without Claude:

```
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\ue_info.ps1 -Engines
powershell -ExecutionPolicy Bypass -File ue-create-project\scripts\create_project.ps1 -ProjectName MyGame -ParentDir C:\Projects -Type Cpp -EnginePath "C:\Program Files\Epic Games\UE_5.9" -Template Empty -Copyright "Copyright MyCompany. All Rights Reserved."
```
