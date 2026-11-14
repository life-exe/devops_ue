---
name: ue-docs
description: Generate Doxygen documentation for an Unreal C++ project using devops_ue (devops_data\Doxyfile, the UE macro filter and the Flat/Dark themes from devops_ue\docs) - fetches the docs submodules when needed, sets the project title/version for the run, reports pages and Doxygen warnings, and can improve doc comments. Use when asked to generate, build, update or publish code documentation / API docs / Doxygen.
---

# Generate documentation

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/generate_docs.ps1" -ProjectPath "<project>" [-Title "<Game>"] [-Version 1.0.0] [-Open]
```

Talk to the user in their language.

* Needs Doxygen (missing -> offer `ue-install-env -Tools doxygen`, i.e. `winget install DimitriVanHeesch.Doxygen`)
  and a C++ project.
* Config: `devops_data\Doxyfile` (created from `devops_ue\setup\Doxyfile.template` when missing; the user's file is
  never edited). Per-run overrides go to `Saved\Docs\Doxyfile.effective`: the project name instead of `"My Project"`
  (or `-Title`), `-Version`, the UE macro filter run with an existing Python (the template uses `py`), the warning
  log, and no theme files when the `devops_ue\docs` submodules can't be fetched.
* The script runs `git submodule update --init --recursive` inside `devops_ue` when the themes/filter are missing
  (needs network; a copied devops_ue without `.git` falls back to the default look).
* Output: `Documentation\html\index.html` (the `OUTPUT_DIRECTORY` of the Doxyfile); `Documentation/` is git-ignored.

## Report

Index path, page count, Doxygen warnings (count + first lines from `Saved\Docs\doxygen_warnings.log`), warnings,
the `Time:` block. If the user wants better docs, offer to add Doxygen comments (`/** ... */`, `@param`, `@return`)
to the public headers with the most warnings - keep the copyright line and `.clang-format` style.
Publishing on GitHub Pages: `devops_ue\github_workflows` has a `doxygen.yml` workflow (`install_workflows.bat`).
