---
name: ue-content-audit
description: Audit an Unreal project's Content - size by folder and file type, largest packages (quick, no editor); with -Deep the editor's asset registry adds size by asset class, unreferenced asset candidates, textures above a size limit and redirectors; with -Validate the engine's DataValidation plugin checks the assets (corrupt/unloadable packages, project validators) and lists errors and warnings; HTML or Markdown report. Use when asked what takes space in the project, why the build/download is big, which assets are unused, or to clean up content (especially before a web build).
---

# Content audit

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/content_audit.ps1" -ProjectPath "<project>" [-Top 20]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/content_audit.ps1" -ProjectPath "<project>" -Deep [-TextureLimit 2048] [-Report Saved\content_audit.md]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/content_audit.ps1" -ProjectPath "<project>" [-Deep] [-Validate [-ValidateAssetType <Class>] [-FailOnIssues]] -Html -Open -Lang ru|en
```

Talk to the user in their language. Read-only: the script never deletes or changes assets.

* **Quick** (default, seconds): `Content` files grouped by top folder and extension, the largest packages
  (`.uasset/.umap` + `.uexp/.ubulk`).
* **`-Deep`** (starts `UnrealEditor-Cmd -run=pythonscript`, 1-3 min, C++ projects must have the editor built):
  size by asset class, **unreferenced candidates** (no hard/soft package reference, not a map/redirector, not named
  in `Config/*.ini`), textures larger than `-TextureLimit` px, redirectors. Run it in the background.
* **`-Validate`** (starts `UnrealEditor-Cmd -run=DataValidation`, about 30 s - 3 min, same editor requirement as `-Deep`): the
  engine's **DataValidation** plugin runs every enabled validator over the `/Game` assets and the errors / warnings go to
  the report, first on the page (columns: severity, asset, message) with the list of validators that ran. This is the
  engine's own checker (corrupt or unloadable packages, localization mistakes, plus any project validator derived from
  `UEditorValidatorBase`, C++ or Blueprint), not a heuristic. `-ValidateAssetType Texture2D` limits it to a class,
  `-FailOnIssues` exits with 1 on errors (CI). Combine with `-Deep`. If a validator's own rules are wanted (naming,
  texture size limits, forbidden references), offer to write one (a C++ `UEditorValidatorBase` subclass in the editor module,
  or an Editor Utility Blueprint): it then runs here and in the editor's Validate Data.
  If an engine plugin's binaries do not match the engine build the editor stops at start-up (seen with `Fab`): the script
  retries without that plugin and warns; the real fix is "Verify" in the Epic Games Launcher.
* `-Report <file.md>` saves all tables as Markdown (relative paths are under the project).
* `-Html` writes a minimal self-contained HTML page with the same tables (a row filter, RU / EN switch, light/dark theme) to
  `Saved\ContentAudit\content_audit.html`; `-Report <file.html>` picks the file; `-Open` opens it in the browser;
  `-Lang ru|en` sets the language the page starts in. The page template is `assets/report.html`.

## Report

Make the HTML report (`-Html -Open -Lang <the user's language>`, with `-Deep` when it was asked for) and tell the user the
path. In the chat show the key tables as Markdown (not everything: the page has the rest). Then recommendations, e.g.: biggest folders worth a look; unreferenced candidates
**to verify** (assets loaded by string path in code/DataTables/config look unreferenced too - check with the
editor's Reference Viewer or a code search before deleting, and delete inside the editor, never from disk);
textures to downscale or set a max size / LOD group (matters most for web builds: download size); redirectors to
fix (Content Browser > Fix Up Redirectors). Plus warnings and the `Time:` block.
