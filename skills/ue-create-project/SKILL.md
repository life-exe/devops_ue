---
name: ue-create-project
description: Create a new Unreal Engine 5 project (C++ or Blueprint) wired up with devops_ue - asks for the project name, project type, copyright, engine version (auto-detected) and start map (empty MainLevel or an Unreal template), then creates the project, runs devops_ue setup, fills configs, copies .clang-format/.gitignore/bat scripts/skills/AGENTS.md, creates A<Name>GameMode for C++ projects and optionally packages the game. Use when asked to create/scaffold/start a new Unreal project.
---

# Create an Unreal Engine project

All heavy lifting is done by `scripts/create_project.ps1`; your job is to collect the answers, run it and report.
Scripts live next to this file: `<skill dir>/scripts/`. Run them with
`powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...`.

Talk to the user in their language.

## 0. Environment

First run the `ue-check-env` skill's script for this skill:
`<skills dir>/ue-check-env/scripts/check_env.ps1 -For create -ProjectDir <target folder>`.
If something required is missing (`[XX]`), stop and offer the fix from its table; continue only when the required
items are in place. Mention `[!!]` items briefly (e.g. Git LFS missing matters for the LFS question at the end).

## 1. Collect answers

Ask in this order. Use `AskUserQuestion` for choices; free text (project name) is asked as a normal message.

0. **Prepared folder?** First look at the current folder. If it contains only `.git`, `.gitmodules`,
   `devops_ue` and optionally `.claude` (the user did `git init` + `git submodule add .../devops_ue` by hand,
   maybe `install_skills.bat project`) - this is the usual start -
   the project is created **in place**: pass `-ProjectDir <current folder>`, propose the folder name as the
   project name and skip the location question. If it has anything else (e.g. a `.uproject`), it is not a target.
   **Check with commands, not by eye** - an empty tool output does not mean an empty folder:
   `Get-ChildItem -Force | Select-Object Name` for the top level and
   `(Get-ChildItem -Force -Recurse .claude | Measure-Object).Count` for the size of `.claude`.
   An existing `.claude` is kept: the script copies the devops_ue skills into `.claude\skills` over the
   same-named skill folders (devops_ue is the source of truth, normally the same files that
   `install_skills.bat project` put there); other skills and files in `.claude` stay untouched.
   If the script warns that "this copy of the skill differs from devops_ue", tell the user and suggest
   `devops_ue\skills\install_skills.bat` (+ `devops_ue\skills\check_skills.ps1` to verify).
1. **Project name** - ask the user to type it. Must match `^[A-Za-z][A-Za-z0-9_]{0,19}$`
   (starts with a letter, letters/digits/underscore, max 20 chars). Re-ask if invalid.
2. **Location** (only when not in place) - parent folder for the project (`<parent>\<Name>`, `-ParentDir`).
   Offer the current folder and its parent. The target folder must not exist, be empty, or contain only
   `.git`, `.gitmodules`, `devops_ue`, `.claude`.
3. **Project type** - `C++` or `Blueprint`.
4. **Copyright** - **always ask, for Blueprint projects too; never invent or default it silently.**
   A Blueprint project has no sources now, but the copyright goes to `DefaultGame.ini` (`CopyrightNotice`),
   `devops_data\config.bat` (`COPYRIGHT_LINE`, used for generated Target/test files), `AGENTS.md`, and to the C++
   module that `ue-web-setup` adds later. Two steps, because an `AskUserQuestion` option cannot take typed text
   (only the built-in "Other / Type something" can):
   1. **Company** - ask as a normal message (free text, together with the project name if convenient):
      "Company / studio name? Empty = none". It goes to `-CompanyName` (`DefaultGame.ini` CompanyName).
   2. **Copyright** - then `AskUserQuestion` with **concrete, already filled-in strings**, never placeholders like
      `<Name>`/`<Company>`: `Copyright <actual company>. All Rights Reserved.` (only if a company was given),
      `Copyright <actual project name>. All Rights Reserved.`; custom text comes through "Other".
   The value is stored without `//`; the script adds `// ` for source files.
5. **Engine version** - run
   `ue_info.ps1 -Engines`
   It prints JSON (`Version`, `Path`, `Association`, `Installed`, `EditorBuilt`, `Source`), newest first.
   * Two or more engines: show them as options (`5.9.0 - C:\Program Files\Epic Games\UE_5.9`), up to 4; mention others in text.
   * Exactly one engine: don't ask (a question needs at least 2 options) - say which engine will be used and
     show it in the final summary, where the user can still change it.
   * None found -> ask for the engine root path (folder that contains `Engine\`).
   * Warn if `EditorBuilt` is false (source build that is not compiled yet).
6. **Start map**
   * `Empty MainLevel` - blank project, empty level `/Game/Maps/MainLevel` set as game + editor startup map.
   * `Unreal template` - then run
     `ue_info.ps1 -Templates -EnginePath "<path>" -Type Cpp|Blueprint`
     and ask which template (show `DisplayName`, pass `Name` to the script). Prefer `Category = Games`
     ones (Third Person, First Person, Top Down, Vehicle, ...).
   * **Variant** - the `Variants` array of the chosen template in the same JSON (C++ templates of UE 5.6+: Third Person has
     Combat / Platforming / SideScrolling, First Person Shooter / Horror, Top Down Strategy / TwinStick, Vehicle OffRoad /
     TimeTrial). If it is not empty, ask which variant (options: the variants plus "Default template level" - the
     template's own level; pass `-Variant <Name>` only for a variant). It is the editor's "Variants" dropdown: the variant
     level becomes the start map and cooked map, its game mode the default one. All variants' code and content are copied
     either way (as the editor does), so the variant can be switched later in Project Settings > Maps & Modes. Empty
     `Variants` (Blueprint templates, other templates) -> do not ask.
7. **Packaging** - package the game right after creation (`Development`, Win64)? Default: no, it takes long.
8. **devops_ue** - default: added as a git submodule (`git submodule add <origin url of this devops_ue>`).
   Only ask if the user mentioned they are offline / want a plain copy -> `-DevopsMode Copy`.

Batch questions 3-7 into one or two `AskUserQuestion` calls where possible, but every one of them must be
asked - none is skipped because of the project type. Before running, show a short summary of all answers
(name, folder, type, company, **copyright**, engine, start map / template / variant, packaging) and get a confirmation.

`AskUserQuestion` limits: 1-4 questions per call, 2-4 options per question, header up to 12 characters.
Never add an option whose meaning is "type it yourself" - that is what the built-in "Other" is for.

## 2. Create the project

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/create_project.ps1" `
  -ProjectName "<Name>" (-ProjectDir "<project folder>" | -ParentDir "<parent>") -Type Cpp|Blueprint `
  -EnginePath "<engine path>" -EngineAssociation "<Association from ue_info>" `
  -Template Empty|<TP_TemplateName> [-Variant <Combat|Shooter|...>] -Copyright "<copyright>" [-CompanyName "<company>"] [-Package]
```

* Pass `-DevopsSource "<path>\devops_ue"` if the script can't find devops_ue itself (it looks next to the
  skill, in `<project>\devops_ue` and in `devops_source.txt` written by `install_skills.bat`).
* C++ build + first editor launch (shader compilation) take many minutes: run the command in the
  background (`run_in_background`) and wait for the notification instead of polling.
* `-SkipBuild` / `-SkipMainLevel` exist for debugging; don't use them by default.

What the script does:

1. Copies the engine template (`TP_Blank`/`TP_BlankBP` for Empty) following its `TemplateDefs.ini`
   (ignored files/folders, renames `TP_*` -> `<Name>` in paths and in `.cpp/.h/.ini/.cs`, shared content packs).
2. Writes `<Name>.uproject` with the engine association.
3. Config: `DefaultGame.ini` - ProjectID, ProjectName, CopyrightNotice, CompanyName, MapsToCook;
   `DefaultEngine.ini` - GameDefaultMap/EditorStartupMap (MainLevel), GlobalDefaultGameMode
   (`/Script/<Name>.<Name>GameMode` for empty C++), ActiveGameNameRedirects/ActiveClassRedirects for C++ templates.
4. C++: creates `Source/<Name>/<Name>GameMode.h/.cpp` (`A<Name>GameMode : AGameModeBase`) unless the template
   already has it, and puts `// <copyright>` as the first line of every `.h/.cpp/.cs`.
5. `git init` and adds `devops_ue` (submodule or copy) unless they already exist, runs `devops_ue\setup.bat`, sets `EnginePath` and
   `COPYRIGHT_LINE` in `devops_data\config.bat`.
6. Copies to the root: `.clang-format`, `.gitignore`, `LICENSE.md`, `README.md`, `generate_project_files.bat`,
   `clean_intermediate_files.bat`, `package_game.bat` (+ `format_all_files.bat`, `run_tests.bat` for C++);
   devops skills -> `.claude\skills\`; `AGENTS.md` (from `devops_ue\setup\AGENTS.md.template`) + `CLAUDE.md` importing it.
7. C++: generates project files, runs clang-format, builds `<Name>Editor Win64 Development`.
8. Empty map: creates `/Game/Maps/MainLevel` via `UnrealEditor-Cmd -run=pythonscript` (`create_main_level.py`).
9. `-Package`: runs `package_game.bat` (output in `<project>\Build`).

## 3. Git: LFS and the first commit

After the project is created (and the report below is shown), ask in one `AskUserQuestion` call:

1. **Git LFS** - "Use Git LFS for assets (.uasset, .umap, textures, audio, video)?"
   Recommend **yes** when the project has template content or will be pushed to GitHub (it rejects files over
   100 MB; large repos without LFS get slow). Needs Git LFS installed (see the environment check).
2. **Commit** - "Make the first commit now?" yes / no (the user may want to look at the files first).
3. **devops_data\config.bat** - keep local (git-ignored, recommended for a team: it holds local engine paths) or
   commit it (fine for a solo project).

Then run (LFS must be set up before the first commit of the assets):

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/finalize_git.ps1" `
  -ProjectDir "<project>" [-UseLfs] [-Commit] [-Message "<message>"] [-CommitLocalConfig]
```

* `-UseLfs`: `git lfs install --local` + `git lfs track` for Unreal assets and media -> `.gitattributes`.
* without `-CommitLocalConfig`: `devops_data/config.bat` is added to `.gitignore`.
* `-Commit`: checks `git config user.name/email` (asks the user to set them if missing), `git add -A`,
  `git commit` (default message `Initial <Name> project`), warns about files over 50 MB without LFS.
* Never pushes. Report the commit hash, file count, files in LFS and the time from its `Time:` block.
  Suggest `gh repo create --private --source . --push` only if the user asks about a remote.

If the user says no to both LFS and commit, skip the script but still offer the `.gitignore` choice for `config.bat`.

## 4. Report

* Path to the `.uproject`, what was created, and every line from the script's `Warnings:` block.
* **Time**: the total from the script's `Time:` block and the longest steps (e.g. build, MainLevel creation, packaging).
* If MainLevel creation failed: tell the user to create it in the editor (File > New Level > Empty Level,
  save as `/Game/Maps/MainLevel`) - configs already point to it. Logs: `<project>\Saved\Logs`.
* If the C++ build failed: show the relevant compiler errors from the output.
* Then go to step 3 (LFS / first commit) - `create_project.ps1` itself never commits.
