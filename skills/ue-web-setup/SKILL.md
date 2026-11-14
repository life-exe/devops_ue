---
name: ue-web-setup
description: Set up an Unreal Engine 5.9+ project for the web (Wasm - WebAssembly + WebGPU) - installs/validates emscripten (emsdk) and sets WASM_EMSDK_ROOT, fixes .uproject plugins for Wasm, writes Wasm project settings (page title, start mode, renderer tiers, mobile policy, isolation headers), adds a C++ module to Blueprint-only projects, adds devops_ue web scripts and the engine web skills, verifies the SDK and optionally builds/packages for the browser. Use when asked to prepare, configure or set up a project for web / browser / Wasm / WebGPU.
---

# Web (Wasm) setup for an Unreal project

Everything is done by `scripts/web_setup.ps1` (run with
`powershell -NoProfile -ExecutionPolicy Bypass -File "<skill dir>/scripts/web_setup.ps1" ...`).
Talk to the user in their language. Source of truth for web details is the engine:
`<Engine>\Engine\Platforms\Wasm\Docs\GettingStarted.md` - read the relevant section when the user asks something this file doesn't cover.

## 1. Check first

Run a read-only check and show the result:

```
web_setup.ps1 -ProjectPath "<project dir or .uproject>" -CheckOnly -SkipVerify
```

It resolves the engine (`-EnginePath`, else `devops_data\config.bat`, else `.uproject` EngineAssociation), and reports:
engine >= 5.9 with `Engine\Platforms\Wasm`, emscripten version (exactly the one from `Wasm_SDK.json`, 6.0.10 for 5.9),
C++ vs Blueprint-only, plugin rules, GameDefaultMap.

## 2. Ask (AskUserQuestion, one call)

1. **Start mode** - `Click` (recommended: the click unlocks sound and pointer lock) or `Auto`.
2. **Renderer tiers** - both mobile tiers (default: deferred on desktop GPUs, forward on phones) or `-ForwardOnly`
   (smaller cook; required when the project uses `r.MobileHDR=False` or mobile MSAA).
3. **Hosting** - where it will run: own server / Vercel / Netlify (headers can be set), itch.io (enable
   *SharedArrayBuffer support* in its embed options), GitHub Pages or a host without header control
   (-> `-InjectIsolationHeaders`).
4. **After setup** - nothing / build editor (`-BuildEditor`) / package Development (`-Package Development`) /
   package Shipping (`-Package Shipping`, for public builds).

Ask separately (plain message) only when relevant:
* **Blueprint-only project** - Wasm in 5.9 needs a C++ module. Ask for permission, then pass `-AddCppModule`
  (adds `Source/<Name>` from the engine's blank C++ template + `A<Name>GameMode`, registers the module, builds the editor;
  the project's current default game mode is not changed).
* **emscripten missing** - installing clones emsdk to `C:\emsdk` (or `-EmsdkDir`) and downloads ~1 GB; confirm first.
* Page title if it should differ from the project name; mobile devices policy (`-MobileDevices Warn|Block|Allow`).
* `AIAssistant` is disabled for the web by default; pass `-KeepAIAssistant` if the user wants to keep it.

## 3. Run

```
web_setup.ps1 -ProjectPath "<project>" -StartMode Click [-ForwardOnly] [-InjectIsolationHeaders] `
  [-PageTitle "<title>"] [-MobileDevices Warn] [-WebSetting Key=Value ...] [-AddCppModule] `
  [-InstallPlaywright] [-BuildEditor] [-Package Development|Shipping]
```

Builds and packaging take many minutes (first Wasm link is slow): run in the background and wait for the notification.

What it does:
1. **emsdk**: validates `WASM_EMSDK_ROOT` / `EMSDK` / AutoSDK (`UE_SDKS_ROOT`); warns about a stale `EMSDK`; installs
   emsdk `install` + `activate` <version> when missing; sets `WASM_EMSDK_ROOT` for the user.
2. **.uproject** (`uproject_web_ready.py`, engine Python): `OnlineSubsystemUtils`/`OnlineSubsystemNull` get
   `PlatformDenyList: ["Wasm"]`, `AllToolsets` and `AIAssistant` disabled (toolsets break the Wasm cook).
3. **Settings** in `Config/DefaultEngine.ini` `[/Script/WasmTargetPlatform.WasmTargetSettings]`: PageTitle, StartMode,
   MobileDevices, bTargetMobileDeferredTier, bInjectIsolationHeaders, any `-WebSetting`; GameDefaultMap -> MapsToCook.
   All keys: `Engine\Platforms\Wasm\Source\Developer\WasmTargetPlatform\Public\WasmTargetSettings.h`.
4. **devops_ue**: root `package_wasm.bat`, `run_wasm.bat`, `setup_emsdk.bat`; `EnginePath` in `devops_data\config.bat`.
5. **Engine web skills** (`web-deploy`, `web-perf-hillclimb`, `web-texture-sets`) -> `.claude\skills`; a Web section in `AGENTS.md`.
6. `RunUAT Turnkey -command=VerifySdk -platform=Wasm` (skip with `-SkipVerify`).
7. Optional editor build and `BuildCookRun -platform=Wasm` into `<project>\Build\Wasm`; `check_stage.py` for Shipping/Test.

## 4. Report

* The summary table and every warning.
* **Time**: the total from the script's `Time:` block and the longest steps (emsdk install, editor build, packaging).
* emsdk was just installed -> the editor and open terminals must be restarted (they read `WASM_EMSDK_ROOT` at start).
* Next steps: run locally with `run_wasm.bat` (never open `index.html` from disk), package with
  `package_wasm.bat Shipping` for anything public, deploy with the `ue-web-deploy` skill.
