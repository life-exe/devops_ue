# Copyright LifeEXE. All Rights Reserved.
# Runs inside the editor (UnrealEditor-Cmd <project> -run=pythonscript -script=content_audit.py) and writes the asset
# registry view of /Game to the JSON file named by the UE_AUDIT_OUT environment variable:
# class, referencers (hard + soft package references), texture dimensions.

import json
import os

import unreal

out_path = os.environ.get("UE_AUDIT_OUT", "")
registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.search_all_assets(True)  # synchronous full scan (commandlets start with an empty registry)

asset_filter = unreal.ARFilter(package_paths=["/Game"], recursive_paths=True, include_only_on_disk_assets=True)
assets = registry.get_assets(asset_filter)
options = unreal.AssetRegistryDependencyOptions(
    include_soft_package_references=True,
    include_hard_package_references=True,
    include_searchable_names=False,
    include_soft_management_references=False,
    include_hard_management_references=False,
)


def tag_value(asset, tag):
    try:
        value = asset.get_tag_value(tag)
    except Exception:
        return ""
    if isinstance(value, tuple):  # (found, value) in some engine versions
        return value[1] if value and value[0] else ""
    return value or ""


rows = []
for asset in assets:
    package = str(asset.package_name)
    if "/__External" in package:  # World Partition external actors/objects belong to their map
        continue
    try:
        referencers = registry.get_referencers(asset.package_name, options) or []
    except Exception:
        referencers = []
    referencers = sorted({str(r) for r in referencers if str(r) != package})
    try:
        asset_class = str(asset.asset_class_path.asset_name)
    except Exception:
        asset_class = str(getattr(asset, "asset_class", ""))
    rows.append({
        "package": package,
        "name": str(asset.asset_name),
        "class": asset_class,
        "referencer_count": len(referencers),
        "referencers": referencers[:10],
        "dimensions": tag_value(asset, "Dimensions"),
    })

with open(out_path, "w", encoding="utf-8") as f:
    json.dump({"assets": rows}, f)
unreal.log("[content_audit] wrote {} assets to {}".format(len(rows), out_path))
