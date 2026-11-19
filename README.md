# Unreal Engine devops

![alt text](https://github.com/life-exe/devops_ue/blob/master/assets/logo.png)

This lightweight repository is a part of [Unreal Engine Automation and Testing course](https://youtube.com/playlist?list=PL2XQZYeh2Hh-PdSglBEm520Eboph1GcA2).
You can use it with any Unreal Engine project to speed up your development process.

The course has its [own wiki](https://lifeexe-art.gitbook.io/unreal-automation).

Each subfolder of the current repo has an additional readme page for further information.

## Features

* UE source automation (clone, setup, build, custom installed build)
* UE projects automation (build, cook, package)
* Game, Client, Server (dedicated, listen) builds
* Code format with .clang-format
* Test automation, code coverage
* Documentation generation with doxygen
* Jenkins' pipelines
* GitHub webhooks, slack notifications, schedules, ngrok etc.
* [AI agent skills](#ai-agent-skills): create a project, check the environment, tests, build, package, docs - in plain words or with `/ue-*` commands

## How To Setup

* Add this repository as a submodule for your UE project:

```
git submodule add https://github.com/life-exe/devops_ue
```

* Launch following bat file inside **devops_ue** folder (you can skip the current step if you don't need docs generation):

```
update_submodules.bat
```

* Next launch the following bat file inside **devops_ue** folder:

```
setup.bat
```

* **Setup.bat** will create **devops_data** folder in the root of your main project with the following artifacts:

```
+- Source
+- Content
+- Config
+- ...
+- devops_ue
|    +- update_submodules.bat
|    +- setup.bat
|    +- ...
+- devops_data
|    +- config.bat
|    +- format_all_files.bat
|    +- generate_project_files.bat
|    +- clean_intermediate_files.bat
|    +- run_tests.bat
|    +- generate_docs.bat
|    +- package_game.bat
|    +- package_wasm.bat
|    +- run_wasm.bat
|    +- setup_emsdk.bat
|    +- .clang-format
|    +- .gitignore
|    +- Doxyfile
|    +- LICENSE.md
|    +- README.md
```

* The main file that you need to config is **config.bat**
* Required variables you need to edit accordingly to your local path in this file are: **EnginePath, ProjectPureName, VersionSelector**
* Commit **config.bat** to your repository if you are working alone, otherwise don't do this and just keep this file as local
* **Doxyfile** is for docs generation with doxygen. You can edit all properties that you need and then commit **Doxyfile** to your repo. Or just delete this file if you don't need docs generation. Most important property to edit:

```
PROJECT_NAME           = "My Project"
```

* All other artifacts are optional, you can move them to the root of your repo, commit and use or just delete them. The final version of your repo might look like this:

```
+- Source
+- Content
+- Config
+- ...
+- devops_ue
|    +- update_submodules.bat
|    +- setup.bat
|    +- ...
+- devops_data
|    +- config.bat
|    +- Doxyfile
+- format_all_files.bat
+- generate_project_files.bat
+- clean_intermediate_files.bat
+- run_tests.bat
+- generate_docs.bat
+- package_wasm.bat
+- run_wasm.bat
+- setup_emsdk.bat
+- .clang-format
+- .gitignore
+- LICENSE.md
+- README.md
```

* Now you can quickly generate project files, format all source files with **.clang-format**, clean intermediates, run tests and docs generation
* More useful scripts can be found inside other folders of **devops_ue**

## AI Agent Skills

The **skills** folder contains skills for AI coding agents ([Claude Code](https://docs.claude.com/en/docs/claude-code), Codex, OpenCode, Antigravity). A skill is a directory with a `SKILL.md` (instructions for the agent) and the scripts it runs. Describe the task in plain words ("check the environment", "create a new C++ project", "run the tests with coverage") or call a skill with `/ue-<name>`: the agent picks the skill, runs the scripts, reads the log and reports the result.

* **Environment:** `ue-check-env`, `ue-install-env`
* **Project:** `ue-create-project`, `ue-upgrade-engine`, `ue-clean`, `ue-content-audit`
* **Code:** `ue-format`, `ue-run-tests`, `ue-add-test`, `ue-docs`, `ue-plugin-create`, `ue-plugin-package`
* **Build and release:** `ue-target-create`, `ue-cook`, `ue-package`
* **Help:** `ue-help`

The skills are a thin layer over the same bat scripts and templates: the repository works without AI, and dangerous operations (deleting, installing, uploading) go through a dry run and a confirmation.

```
skills\install_skills.bat
skills\install_skills.bat global all
```

Then type `/ue-help` in your agent: it opens an HTML overview of all skills with their scripts and parameters. The same page is published online: **[life-exe.github.io/devops_ue](https://life-exe.github.io/devops_ue/)**. Details: [skills/README.md](skills/README.md).

## Web (Wasm + WebGPU) Setup from Scratch

Starting with **Unreal Engine 5.9**, official web deployment is supported via the **Wasm** target (WebAssembly 64-bit with threads + WebGPU).

Official guides: Epic's tutorial [Getting started with UE 5.9 on the web (Wasm)](https://dev.epicgames.com/community/learning/tutorials/k8z03/unreal-engine-getting-started-with-ue-5-9-on-the-web-wasm) and the engine docs in `Engine\Platforms\Wasm\Docs` (start with `GettingStarted.md`).

Follow these steps to set up, build, and run a web project from scratch:

### 1. Prerequisites
* **Unreal Engine 5.9+** (with Wasm platform libraries included).
* **C++ Project**: Pure Blueprint-only projects are not supported for Wasm in Preview. If your project is Blueprint-only, add at least one C++ class via **Tools > New C++ Class** in the editor.
* **[Emscripten SDK 6.0.10](https://github.com/emscripten-core/emsdk)**: Strictly required by the engine. Run:
  ```bat
  devops_data\setup_emsdk.bat
  ```
  *(or `devops_ue\setup\setup_emsdk.bat`)* — it clones `emsdk`, activates version `6.0.10`, and registers the `WASM_EMSDK_ROOT` environment variable.

### 2. Project Configuration
* **Maps to Cook**: Ensure all game maps and the menu map are registered in `Config/DefaultGame.ini`:
  ```ini
  [/Script/UnrealEd.ProjectPackagingSettings]
  +MapsToCook=(FilePath="/Game/Maps/Map1")
  +MapsToCook=(FilePath="/Game/Maps/Map2")
  ```
* **Default Game Map**: Set your entry map in `Config/DefaultEngine.ini`:
  ```ini
  [/Script/EngineSettings.GameMapsSettings]
  GameDefaultMap=/Game/Maps/Map1.Map1
  ```
* **Engine Path**: In your `devops_data\config.bat`, ensure `EnginePath` points to UE 5.9+.

### 3. Packaging
Run the packaging script (specify `Shipping` for release or `Development` for debugging):
```bat
devops_data\package_wasm.bat Shipping
```
This builds C++ with Emscripten, cooks assets/shaders for WebGPU, packages IoStore containers, and compresses artifacts using Brotli into `%ArchivePath%\Wasm`.

### 4. Running & Testing
WebAssembly modules with multithreading and WebGPU require specific Cross-Origin isolation headers (`COOP`/`COEP`) and cannot be opened via `file:///`. Use the runner script:
```bat
devops_data\run_wasm.bat
```
*(or run the generated `Build\Play_<ProjectName>.bat`)*. It starts a local server with all required headers and opens the game in your default browser.

## Resources

* [youtube playlist of the course](https://www.youtube.com/watch?v=25Ru2h4G0aQ&list=PL2XQZYeh2Hh-PdSglBEm520Eboph1GcA2)
* [wiki](https://lifeexe-art.gitbook.io/unreal-automation)
* [docs](https://life-exe.github.io/UnrealTPSGame)

## Enjoy! 🚀️
