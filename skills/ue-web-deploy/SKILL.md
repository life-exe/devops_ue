---
name: ue-web-deploy
description: Deploy a packaged Unreal Engine web (Wasm) build to itch.io (butler), Vercel or a GitHub release, and install/check the tools for it (itch.io butler, Vercel CLI, GitHub CLI). Use when asked to publish, upload, deploy or release a web/browser build, or to install butler / vercel / gh.
---

# Deploy an Unreal web (Wasm) build

Scripts: `<skill dir>/scripts/install_tools.ps1`, `<skill dir>/scripts/deploy_web.ps1`
(run with `powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...`). Talk to the user in their language.

**Rules**
* Uploading publishes the game: always run with `-DryRun` first, show the summary (target, files, size, warnings,
  exact command) and get an explicit "yes" before the real upload. Ask again for every new upload.
* Never ask for, type or store tokens/passwords. Logins are interactive and done by the user:
  `! butler login`, `! vercel login`, `! gh auth login` (CI may use `BUTLER_API_KEY`, `VERCEL_TOKEN`, `GH_TOKEN`).
* Public builds must be **Shipping**: `check_stage.py` (engine release scan) blocks Development builds.
  `-AllowDevelopment` only for a private test the user explicitly asked for.

## 1. Tools

```
install_tools.ps1 [-Tools butler,vercel,gh] [-CheckOnly]
```

* **butler** - downloaded from the official channel (`broth.itch.zone`) to `%LOCALAPPDATA%\itch-butler`, added to user PATH.
* **Vercel CLI** - `npm install -g vercel` (installs Node.js LTS via winget if npm is missing).
* **GitHub CLI** - `winget install GitHub.cli`.

It prints a table with the version and login state. For each "not logged in" tool needed for the chosen target,
ask the user to run the login command with `!` and re-check with `-CheckOnly`.

## 2. Build to deploy

`deploy_web.ps1` finds the newest stage (folder with `index.html`) in `<project>\Build\Wasm\Wasm`, `Build\Wasm` or
`Saved\StagedBuilds\Wasm`; `-Stage <folder>` overrides. No build yet -> package first:
`package_wasm.bat Shipping` (or the `ue-web-setup` skill with `-Package Shipping`). Long: run in the background.

## 3. Ask (AskUserQuestion)

* **Target**: itch.io / Vercel / GitHub release.
* itch.io: `user/game` (the page must exist: itch.io/game/new, *Kind of project* = **HTML**), channel (default `html5`),
  optional version label.
* Vercel: project name (default: project name in kebab case), team scope if not personal, preview or production (`-Prod`).
* GitHub: tag (default `web-<date>`), repo if not the project's `origin`.

## 4. Deploy

```
deploy_web.ps1 -ProjectPath "<project>" -Target itch   -ItchTarget user/game [-ItchChannel html5] [-Version 1.0.0] [-DryRun]
deploy_web.ps1 -ProjectPath "<project>" -Target vercel [-VercelProject name] [-VercelScope team] [-Prod] [-DryRun]
deploy_web.ps1 -ProjectPath "<project>" -Target github [-GitHubTag web-1.0] [-GitHubRepo owner/repo] [-DryRun]
```

What happens:
1. `check_stage.py` on the stage (manifests, sha1s, no debug files, release scan).
2. The stage is mirrored to `<project>\Saved\WebDeploy\<target>\site` without debug files and `.br` siblings
   (these hosts don't serve them with `Content-Encoding: br`); file count/size limits are checked.
3. Target:
   * **itch** - `butler push site user/game:channel` (incremental patches). Then tell the user to set once on the
     itch.io page: upload marked *played in the browser*, **Embed options > SharedArrayBuffer support = ON**
     (without it the game stops at the browser check), viewport size, fullscreen button.
   * **vercel** - writes `vercel.json` (COOP/COEP/CORP, `Cache-Control: no-cache`, `application/wasm`), `vercel link`
     on the first run (`.vercel` is kept in the site folder), `vercel deploy [--prod]`, then the engine's
     `webdoctor.py` checks the live URL (headers, MIME, ranges, isolation). Preview URLs can be behind Vercel
     Authentication - then webdoctor fails; check in a browser or use `-Prod`.
   * **github** - zips the site and creates/updates a release (`gh release create/upload`). A release is a download,
     not a hosted page: players unzip and run it with a local server (`run_wasm.bat`).

## 5. Report

Page/URL, what was uploaded (files, size), warnings, and the manual itch.io settings if the target was itch.
If something fails, show the tool's error; the usual causes are a missing login, a Development build, or host limits.
More hosting details: `<Engine>\Engine\Platforms\Wasm\Docs\Deploy.md`.
