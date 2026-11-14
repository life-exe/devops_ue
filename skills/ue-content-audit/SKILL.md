---
name: ue-content-audit
description: Audit an Unreal project's Content - size by folder and file type, largest packages (quick, no editor); with -Deep the editor's asset registry adds size by asset class, unreferenced asset candidates, textures above a size limit and redirectors; optional Markdown report. Use when asked what takes space in the project, why the build/download is big, which assets are unused, or to clean up content (especially before a web build).
---

# Content audit

```
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/content_audit.ps1" -ProjectPath "<project>" [-Top 20]
powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/content_audit.ps1" -ProjectPath "<project>" -Deep [-TextureLimit 2048] [-Report Saved\content_audit.md]
```

Talk to the user in their language. Read-only: the script never deletes or changes assets.

* **Quick** (default, seconds): `Content` files grouped by top folder and extension, the largest packages
  (`.uasset/.umap` + `.uexp/.ubulk`).
* **`-Deep`** (starts `UnrealEditor-Cmd -run=pythonscript`, 1-3 min, C++ projects must have the editor built):
  size by asset class, **unreferenced candidates** (no hard/soft package reference, not a map/redirector, not named
  in `Config/*.ini`), textures larger than `-TextureLimit` px, redirectors. Run it in the background.
* `-Report <file.md>` saves all tables (relative paths are under the project).

## Report

Show the tables as Markdown. Then recommendations, e.g.: biggest folders worth a look; unreferenced candidates
**to verify** (assets loaded by string path in code/DataTables/config look unreferenced too - check with the
editor's Reference Viewer or a code search before deleting, and delete inside the editor, never from disk);
textures to downscale or set a max size / LOD group (matters most for web builds: download size); redirectors to
fix (Content Browser > Fix Up Redirectors). Plus warnings and the `Time:` block.
