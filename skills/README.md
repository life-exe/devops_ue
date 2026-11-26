# Skills

[Claude Code](https://docs.claude.com/en/docs/claude-code) skills for Unreal Engine projects.

📺 **How to use the skills: watch the video [youtu.be/vwrg9hiz7TY](https://youtu.be/vwrg9hiz7TY)**

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
| `ue-content-audit` | Content size by folder/type/class, largest packages, unreferenced candidates, big textures, redirectors; `-Validate` runs the engine's DataValidation plugin (errors/warnings per asset, CI exit code); Markdown or HTML report |
| `ue-format` | clang-format over Source (or changed files / chosen paths / plugins), rewrites only files that differ; `-Check` for CI |
| `ue-cook` | BuildCookRun cook only (Win64/Linux/Wasm, Game/Client/Server, incremental), reports cooked size and cook errors |
| `ue-add-test` | Writes real automation tests for a given class (spec/legacy from the templates), offers a separate test module, runs them until green |
| `ue-plugin-create` | Creates a C++ plugin skeleton (Runtime/Editor/Developer module, optional Editor module and Content), wires it into the game Build.cs |
| `ue-plugin-package` | Packages a plugin with UAT BuildPlugin for chosen platforms, checks binaries, optional zip / Fab strict includes |
| `ue-target-create` | Creates Client / Server / Editor target rules (`Source\<Name>Client.Target.cs` ...) from the project's game target |
| `ue-help` | Lists all skills with descriptions, scripts and parameters, where they are installed; recommends a skill for a task |

The same overview without an agent: `powershell -ExecutionPolicy Bypass -File ue-help\scripts\skills_info.ps1`
(`-Name <skill>` details, `-Full` everything, `-Where` install folders, `-Format Markdown|Json`, `-Lang ru|en|both`).
`-Format Html -Open` writes a self-contained help page (a minimal table with search, groups, RU/EN switch, parameters of every script) and opens it
in the browser; `/ue-help` does this by default.

The same page is published to GitHub Pages by `.github/workflows/pages.yml` on every push to `master` that touches `skills/`
(built with `-Format Html -Public`: no local paths or install locations, the language follows the browser).
One-time setup: repository Settings > Pages > Build and deployment > Source: GitHub Actions.

## Install

```
install_skills.bat                          - asks: [G]lobal or [P]roject, then the agent
install_skills.bat global [agent]           - %USERPROFILE%\...: available in every folder
install_skills.bat global all               - install globally for all agents (Claude Code, Codex, OpenCode, Antigravity)
install_skills.bat project [agent]          - <project>\... (the folder that holds devops_ue): only this project, can be committed
```

`agent` (default `claude`):

| agent | project folder | global folder |
|-------|----------------|---------------|
| `claude` | `.claude\skills` | `%USERPROFILE%\.claude\skills` |
| `codex`, `opencode` | `.agents\skills` | `%USERPROFILE%\.agents\skills` |
| `antigravity` | `.agents\skills` | `%USERPROFILE%\.gemini\antigravity\skills` |
| `all` | all of the above | all of the above |

The skills are plain `SKILL.md` + scripts, the same for every agent; only the folder the agent reads differs.
OpenCode also reads `.claude\skills`, so installing both for it duplicates the skills (harmless). Paths follow each
tool's docs at the time of writing - if an agent does not see the skills, check its current docs.

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
