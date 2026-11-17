---
name: ue-help
description: Help for the devops_ue skills - lists every ue-* skill with what it does, which script and parameters it has, where it is installed, and recommends the right skill for a task. Use when asked what skills / commands are available, what the agent can do for an Unreal project, how to use a skill, or which skill to pick.
---

# devops_ue skills help

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/skills_info.ps1" [-Name <skill>] [-Full] [-Where] [-Lang ru|en|both] [-Format Table|Markdown|Json]
```

## Language first

**Before running the script, ask which language to print the descriptions in**, unless the user already named it
(`/ue-help ru`, "по-русски", "in English", "both") - the bare `/ue-help` carries no language signal, so do not guess it.
Use the question tool with three options: **Русский** (`-Lang ru`), **English** (`-Lang en`), **Both / Оба** (`-Lang both`).
Then talk to the user in that language. Descriptions for `ru` come from `summaries.ru.json`; a new skill needs an entry
there, otherwise its Russian text falls back to English.

* No arguments: all skills with a one-line description (read from each `SKILL.md`, so the list is always current).
* `-Name ue-cook` (or just `cook`): full description, the script file(s), their usage lines and every parameter
  with type, default and required flag.
* `-Full`: the same for all skills. `-Where`: also the folders where each skill is installed (user / project, per agent).
* `-Format Markdown` gives a table for docs, `-Format Json` a machine-readable dump.

## What to do

1. Ask the language (see above), then run the script with `-Lang` (no other arguments for a general question, `-Name` when the user asks about one skill).
2. Show the result as a Markdown table / short list, not a raw dump. Group by purpose:
   * environment: `ue-check-env`, `ue-install-env`
   * project: `ue-create-project`, `ue-upgrade-engine`, `ue-clean`, `ue-content-audit`
   * code: `ue-format`, `ue-run-tests`, `ue-add-test`, `ue-docs`, `ue-plugin-create`, `ue-plugin-package`
   * build and release: `ue-target-create`, `ue-cook`, `ue-package`
3. If the user described a task, name the one or two skills that fit and the next step ("run `/ue-cook`").
4. A skill listed by the script but missing from the agent's list means the installed copy is old: run
   `devops_ue\skills\install_skills.bat` (see `check_skills.ps1`).
