# Copyright LifeEXE. All Rights Reserved.
# Makes a .uproject web (Wasm) ready. Run with the engine's Python:
#   python -I uproject_web_ready.py <Project.uproject> [--add-module <Name>] [--keep-ai-assistant]
# Prints one line per change.

import argparse
import json

# online subsystems don't run in a browser (engine web-deploy skill, --web-ready)
WEB_DENY_PLUGINS = ["OnlineSubsystemUtils", "OnlineSubsystemNull"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("uproject")
    parser.add_argument("--add-module", default="")
    parser.add_argument("--keep-ai-assistant", action="store_true")
    args = parser.parse_args()

    with open(args.uproject, "r", encoding="utf-8-sig") as f:
        descriptor = json.load(f)

    changes = []
    plugins = descriptor.setdefault("Plugins", [])

    def entry(name):
        found = next((p for p in plugins if p.get("Name") == name), None)
        if found is None:
            found = {"Name": name, "Enabled": True}
            plugins.append(found)
        return found

    for name in WEB_DENY_PLUGINS:
        deny = entry(name).setdefault("PlatformDenyList", [])
        if "Wasm" not in deny:
            deny.append("Wasm")
            changes.append(f"{name}: PlatformDenyList += Wasm")

    # AllToolsets turns on game feature plugins -> Wasm cook fails (GameFeatureData rule missing)
    disabled = ["AllToolsets"] + ([] if args.keep_ai_assistant else ["AIAssistant"])
    for name in disabled:
        e = entry(name)
        if e.get("Enabled", True):
            e["Enabled"] = False
            changes.append(f"{name}: Enabled = false")

    if args.add_module:
        modules = descriptor.setdefault("Modules", [])
        if not any(m.get("Name") == args.add_module for m in modules):
            modules.insert(0, {"Name": args.add_module, "Type": "Runtime", "LoadingPhase": "Default"})
            changes.append(f"Modules += {args.add_module}")

    if changes:
        with open(args.uproject, "w", encoding="utf-8", newline="\r\n") as f:
            json.dump(descriptor, f, indent="\t")
            f.write("\n")
    for c in changes:
        print("  uproject: " + c)
    if not changes:
        print("  uproject: already web ready")


if __name__ == "__main__":
    main()
