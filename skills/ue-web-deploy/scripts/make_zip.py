# Copyright LifeEXE. All Rights Reserved.
"""Build the zip that a deploy plan describes (engine deploy.py --host zip writes only the plan).

Run with the engine Python (stdlib only, no 7z):
  python -I make_zip.py <deploy-plan.json> <stage> <out.zip> [--keep-prefix]

- packs only the plan's "objects" (deploy.py already left out .br, _headers, debug files, ...)
- index.html at the archive root by default (the "<prefix>/" of the plan keys is stripped), as itch.io and similar
  portals expect; --keep-prefix keeps "<prefix>/..." paths
- checks every file exists in the stage with the plan's size before packing
- ZIP64 (stages are 100-300 MB+), deflate level 6
- writes <out>.zip.tmp, verifies it (testzip, entry count, index.html location), then renames it
"""

import argparse
import json
import sys
import zipfile
from pathlib import Path


def fail(message):
    print(f"make_zip: {message}", file=sys.stderr)
    sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("plan", type=Path, help="deploy-plan.json from deploy.py --host zip")
    parser.add_argument("stage", type=Path, help="the staged Wasm folder (the one with index.html)")
    parser.add_argument("out", type=Path, help="zip file to write")
    parser.add_argument("--keep-prefix", action="store_true", help="keep <prefix>/ in archive paths")
    args = parser.parse_args()

    if not args.plan.is_file():
        fail(f"plan not found: {args.plan}")
    if not (args.stage / "index.html").is_file():
        fail(f"not a stage (no index.html): {args.stage}")

    plan = json.loads(args.plan.read_text(encoding="utf-8"))
    objects = plan.get("objects") or []
    if not objects:
        fail("the plan has no objects")
    prefix = (plan.get("prefix") or "").strip("/")
    prefix_dir = prefix + "/" if prefix else ""

    # plan key -> stage file and archive name
    entries = []
    for o in objects:
        key = o["key"]
        rel = key[len(prefix_dir):] if prefix_dir and key.startswith(prefix_dir) else key
        src = args.stage / rel
        if not src.is_file():
            fail(f"missing in stage: {rel}")
        if src.stat().st_size != o["size"]:
            fail(f"size differs from plan: {rel} ({src.stat().st_size} != {o['size']}) - re-run deploy.py on this stage")
        entries.append((src, key if args.keep_prefix else rel))

    index_name = f"{prefix_dir}index.html" if args.keep_prefix else "index.html"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.out.with_name(args.out.name + ".tmp")
    if tmp.exists():
        tmp.unlink()

    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as z:
        for src, name in entries:
            z.write(src, name)

    with zipfile.ZipFile(tmp) as z:
        names = z.namelist()
        bad = z.testzip()
    if bad:
        tmp.unlink()
        fail(f"corrupt entry in the archive: {bad}")
    if index_name not in names:
        tmp.unlink()
        fail(f"{index_name} is not where it should be in the archive")
    if len(names) != len(objects):
        tmp.unlink()
        fail(f"{len(names)} entries, the plan has {len(objects)}")

    tmp.replace(args.out)
    raw = sum(o["size"] for o in objects)
    print(f"ok: {args.out} - {len(names)} files, {raw / 1e6:.1f} MB raw, {args.out.stat().st_size / 1e6:.1f} MB zipped"
          f"{' (prefix kept: ' + prefix_dir + ')' if args.keep_prefix and prefix_dir else ''}")


if __name__ == "__main__":
    main()
