---
name: ue-web-deploy
description: Deploy a packaged Unreal Engine web (Wasm) build to itch.io (butler), Vercel or a GitHub release, or build a zip for portals, and install/check the tools for it (itch.io butler, Vercel CLI, GitHub CLI). Use when asked to publish, upload, deploy, zip or release a web/browser build, or to install butler / vercel / gh.
---

# Deploy an Unreal web (Wasm) build

Scripts: `<skill dir>/scripts/install_tools.ps1`, `<skill dir>/scripts/deploy_web.ps1`, `<skill dir>/scripts/make_zip.py`
(run the .ps1 with `powershell -NoProfile -ExecutionPolicy Bypass -File <script> ...`). Talk to the user in their language.

**Rules**
* Uploading publishes the game: always run with `-DryRun` first, show the summary (target, files, size, warnings,
  exact command) and get an explicit "yes" before the real upload. Ask again for every new upload.
* Never ask for, type or store tokens/passwords. Logins are interactive and done by the user:
  `! butler login`, `! vercel login`, `! gh auth login` (CI may use `BUTLER_API_KEY`, `VERCEL_TOKEN`, `GH_TOKEN`).
  If butler was installed after this Claude Code session started, it is not on the session's PATH and
  `butler login` fails with "not recognized": use the command the scripts print, e.g.
  `! & "C:\Users\<user>\AppData\Local\itch-butler\butler.exe" login` (new terminals / a restarted Claude Code see it on PATH).
* Public builds must be **Shipping**: the script refuses a Development stage (`ue-query-args=all` in `index.html`)
  and a stage that fails `check_stage.py` (engine release scan). `-AllowDevelopment` only for a private test the
  user explicitly asked for.
* Never edit the engine web skills in `.claude\skills` (`web-deploy`, ...): an engine update overwrites them.

## 0. Environment

Run `<skills dir>/ue-check-env/scripts/check_env.ps1 -For deploy -ProjectDir <project>` first: it shows the engine
Python, Node.js/npm, Vercel CLI, GitHub CLI, butler and their login state in one table.

## 1. Tools and preflight

```
install_tools.ps1 [-Tools butler,vercel,gh] [-CheckOnly]
```

* **butler** - downloaded from the official channel (`broth.itch.zone`) to `%LOCALAPPDATA%\itch-butler`, added to user PATH.
* **Vercel CLI** - `npm install -g vercel` (installs Node.js LTS via winget if npm is missing).
* **GitHub CLI** - `winget install GitHub.cli`.

It prints a table with the version and login state. For each "not logged in" tool needed for the chosen target,
ask the user to run the login command with `!` and re-check with `-CheckOnly`.

For a **zip** (target `zip` or `github`) no external archiver is needed - **do not require 7z/zip**. `deploy_web.ps1`
checks what it needs itself: the engine Python (`Engine\Binaries\ThirdParty\Python3\Win64\python.exe`), free disk
space of about **2x the stage** (zip + extracted copy for the test), and Playwright only when `-TestZip` is used.

## 2. Build to deploy

`deploy_web.ps1` takes the stage (folder with `index.html`) from `<project>\Build\Wasm\Wasm`, `Build\Wasm` or
`Saved\StagedBuilds\Wasm`, in that order; `-Stage <folder>` overrides. No build yet -> package first:
the `ue-package` skill with `-Platform Wasm` (Shipping by default; it also runs the release scan), or
`package_wasm.bat Shipping`. Long: run in the background.
An engine `FileOpenOrder\` folder in the stage is never uploaded (packaging moves it to `Build\Wasm-FileOpenOrder`).

## 3. Ask (AskUserQuestion)

* **Target**: itch.io (butler) / Vercel / GitHub release / zip only (for a portal upload by hand).
* itch.io: `user/game` (the page must exist: itch.io/game/new, *Kind of project* = **HTML**), channel (default `html5`),
  optional version label, and **who will see it**: a check (page visibility **Draft** or **Restricted**,
  itch.io Edit game -> Visibility & access) or a release (**Public** - the build is public the moment the push
  finishes). For a new page recommend Draft, and Public only after the game ran in the browser. Repeat it in the
  confirmation before the real upload ("the page is Draft / Public: ... will see this build").
* Vercel: project name (default: project name in kebab case), team scope if not personal, preview or production (`-Prod`),
  and optionally a link preview image (`-OgImage`, with title/description) for sharing the URL.
* GitHub: tag (default `web-<prefix>`), repo if not the project's `origin`.
* zip / GitHub: run the boot test on the archive (`-TestZip`)?

## 4. Deploy

```
deploy_web.ps1 -ProjectPath "<project>" -Target itch   -ItchTarget user/game [-ItchChannel html5] [-Version 1.0.0] [-DryRun]
deploy_web.ps1 -ProjectPath "<project>" -Target vercel [-VercelProject name] [-VercelScope team] [-Prod] [-TestDeploy] [-OgImage <png/jpg> [-OgTitle ..] [-OgDescription ..] [-SiteUrl https://domain] [-OgSave]] [-DryRun]
deploy_web.ps1 -ProjectPath "<project>" -Target github [-GitHubTag web-1.0] [-GitHubRepo owner/repo] [-TestZip] [-DryRun]
deploy_web.ps1 -ProjectPath "<project>" -Target zip    [-Prefix v1] [-TestZip]
```

What happens:
1. Development check and `check_stage.py` on the stage (manifests, sha1s, no debug files, release scan).
2. The stage is mirrored to `<project>\Saved\WebDeploy\<target>\site` without debug files, `FileOpenOrder` and `.br`
   siblings (these hosts don't serve them with `Content-Encoding: br`); file count/size limits are checked.
3. Target:
   * **itch** - `butler push site user/game:channel` (incremental patches). Then the script waits (up to ~2 min)
     until itch.io has processed the build and prints the channel row (build id, version); a new channel exists only
     after that, so "still processing" is a warning, not a failure (`butler status user/game` later).
     **After the first push to a channel the page shows**
     `There was a problem loading your project: You've selected a HTML5 game but haven't configured how your project is embedded`
     - expected until the page is configured once (Edit game): Kind of project HTML -> Uploads: mark the channel upload
     *This file will be played in the browser* -> Embed options: viewport (e.g. 1280x720), **SharedArrayBuffer support
     ON** (without it the game stops at the browser check), Fullscreen button -> Save -> reopen Edit game and check
     SharedArrayBuffer stayed on -> Visibility: Public only after the game runs.
   * **vercel** - Vercel rejects files over **100 MB**, and the game `.wasm` is bigger raw (e.g. 133 MB). So the
     script uploads `<Game>.wasm.br` **instead of** `<Game>.wasm` (and any other >100 MB file that has a `.br`
     sibling) and serves it at the original URL: `vercel.json` gets a `rewrites` entry (`/<path>.wasm` ->
     `/<path>.wasm.br`) and headers `Content-Type: application/wasm` + `Content-Encoding: br` for that path - the
     browser decodes it, so the sha1 in `wasm-cache.json` still matches. **Never** for `.ucas/.utoc/.pak`: they are
     read with Range requests and a compressed range breaks the engine; a container over 100 MB stops the deploy with
     an error (use another host or more pak chunks). Everything else is uploaded raw (Vercel compresses it and
     answers Range with 206). The limit is checked after the swap. Also: COOP/COEP/CORP, `Cache-Control: no-cache`,
     MIME types; `.vercelignore` (`.env*`, `.vercel`) is always written - `vercel link` puts `.env.local` with a
     token into the site folder. Then `vercel link` on the first run (it tries to connect the game's git repo to the
     project because the site folder is inside it - the script disconnects it again: deploys come only from here), `vercel deploy [--prod]`, the engine's
     `webdoctor.py` on the live URL (headers, MIME, ranges, isolation, "whole-file .wasm GET is complete (br)"),
     and with `-TestDeploy` the boot test `webrun.py --url <url>/index.html` (`--out %TEMP%\wr_vercel`).
     Preview URLs can be behind Vercel Authentication - then webdoctor fails; check in a browser or use `-Prod`.
     **Link preview**: the project's own place for it is `devops_data\web\head.html` (OpenGraph/Twitter tags,
     canonical, ...) + `devops_data\web\public\*` (the image) - packaging adds them to every web build for any host
     (`devops_ue\package\web_page_extras.ps1`, between `<!-- project-head:begin/end -->` markers). If the project
     has it, nothing is needed at deploy time. `-OgImage` (with `-OgTitle`, `-OgDescription`) is the quick way: the
     image is copied to the site as `og.<ext>` and the tags (`og:title/description/image/url`, image size,
     `twitter:card=summary_large_image`, `description`) go into the **uploaded** `index.html` between the same markers -
     a block from `devops_data\web` is replaced, never duplicated; the stage stays untouched (`index.html` is in no
     manifest). Add `-OgSave` to write them to `devops_data\web` too (tell the user to commit it) - recommend it for a
     project that will be deployed again. `og:image` must be absolute: `-SiteUrl` or, with `-Prod`,
     `https://<project>.vercel.app`; without either the tags are skipped with a warning (preview URLs are behind auth
     anyway). After the deploy the script HEADs the page's `og:image` (whichever way it got there, with retries) and
     warns if it is unreachable (another domain -> `-SiteUrl`). Image: PNG/JPG under ~1 MB, 1200x630 (1.91:1) or
     16:9. Messengers cache previews: check with opengraph.xyz.
   * **zip** - see below; nothing is uploaded.
   * **github** - builds the zip (below) and creates/updates a release (`gh release create/upload`). A release is a
     download, not a hosted page: players unzip and run it with a local server (`run_wasm.bat`).

### Zip (target zip / github)

The engine's `deploy.py --host zip` writes **only a plan** (`deploy-plan.json`: the objects, `.br` and `_headers` left
out), not the archive. The archive is built by `make_zip.py` (stdlib `zipfile`, ZIP64, deflate 6, engine Python):

```
python -I make_zip.py <plan dir>\deploy-plan.json <stage> <out.zip> [--keep-prefix]
```

It packs only the plan's objects, checks each file exists with the plan's size, puts `index.html` at the archive root
(the plan's `<prefix>/` stripped, as itch.io-like portals expect; `--keep-prefix` keeps it), writes `<out>.zip.tmp`,
verifies it (testzip, entry count, `index.html`) and renames it. `deploy_web.ps1 -Target zip` runs both steps.

* **Prefix**: `-Prefix`, else the short HEAD commit, else `v<N>` (next free number) when the repo has no commits.
* **Output**: `<project>\Build\WasmDeploy\<Project>-web-<prefix>.zip` (plan in `Build\WasmDeploy\plan-<prefix>`).
* **Test** (`-TestZip`): extracts to `%TEMP%\wz_<prefix>` and runs `webrun.py run --fixture boot --out %TEMP%\wr_<prefix>`;
  reports PASS and READY seconds.
* Tell the user: a zip host does not serve the `.br` copies, so the download is ~3x larger than from the stage
  (e.g. READY 25 s instead of 9 s). For their own server use `deploy.py --host static`; for Vercel use `-Target vercel`.

## Browser load test (webrun.py)

`webrun.py --out` **must be short (~40 characters max)**, e.g. `%TEMP%\wr_<name>` or `<project>\Saved\wr\<name>`; the
same for a folder a zip is extracted to. Its Chrome profile lives in `<out>\profile`, and with a long path the service
worker's Cache Storage paths pass 260 characters: the run fails with `The game script could not be loaded` /
`net::ERR_FAILED` while `?sw=0` passes and the build itself is fine.

## 5. Report

Page/URL or archive path, what was uploaded/packed (files, raw size, zip size), boot test result (READY), warnings,
and for itch: the channel row (or "still processing"), the page visibility, and - after a first push - the embed
error text above with the steps that remove it.
**Time**: the total from the script's `Time:` block and how long the upload / zip itself took.
If something fails, show the tool's error; the usual causes are a missing login, a Development build, host limits
or a stale skill copy (the script warns; fix with `devops_ue\skills\install_skills.bat`).
More hosting details: `<Engine>\Engine\Platforms\Wasm\Docs\Deploy.md`; overview: Epic's tutorial
[Getting started with UE 5.9 on the web (Wasm)](https://dev.epicgames.com/community/learning/tutorials/k8z03/unreal-engine-getting-started-with-ue-5-9-on-the-web-wasm).
