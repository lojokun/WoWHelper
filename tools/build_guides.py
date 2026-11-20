#!/usr/bin/env python3
"""Validate the JSON guides and pack them into the addon.

Each guide in guides/**/*.json is checked, minified and written to
addon/WoWHelper/Guides/<id>.lua as a JSON string. The addon decodes the JSON at
login, so JSON stays the only guide format end to end.

Usage:
    python tools/build_guides.py               # validate + build
    python tools/build_guides.py --check       # validate only
    python tools/build_guides.py --install "<WoW>\\_forever_\\Interface\\AddOns"
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUIDES_DIR = ROOT / "guides"
ADDON_DIR = ROOT / "addon" / "WoWHelper"
OUT_DIR = ADDON_DIR / "Guides"

ACTIONS = {
    "accept", "complete", "turnin", "goto", "fly", "flightpath",
    "sethearth", "hearth", "train", "buy", "level", "note",
}
QUEST_ACTIONS = {"accept", "complete", "turnin"}
CLASSES = {
    "warrior", "paladin", "hunter", "rogue", "priest", "shaman",
    "mage", "warlock", "druid",
}
RACES = {
    "human", "dwarf", "nightelf", "gnome", "orc", "scourge", "undead",
    "tauren", "troll", "skyborne",
}
GUIDE_KEYS = {
    "$schema", "schemaVersion", "id", "title", "author", "description", "faction",
    "races", "classes", "minLevel", "maxLevel", "next", "zone", "sources", "steps",
}
STEP_KEYS = {
    "action", "text", "quest", "questId", "objective", "npc", "zone", "x", "y",
    "radius", "location", "level", "item", "note", "classes", "races", "optional",
}


class Problems:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, where: str, msg: str) -> None:
        self.errors.append(f"ERROR   {where}: {msg}")

    def warn(self, where: str, msg: str) -> None:
        self.warnings.append(f"WARNING {where}: {msg}")


def check_tokens(p: Problems, where: str, value, allowed: set[str], what: str) -> None:
    if value is None:
        return
    if not isinstance(value, list) or not value:
        p.error(where, f"'{what}' must be a non-empty list")
        return
    for v in value:
        if not isinstance(v, str) or v.lower().replace(" ", "") not in allowed:
            p.error(where, f"unknown {what[:-2] if what.endswith('es') else what} '{v}'")


def validate_guide(p: Problems, path: Path, g: dict, zones: dict) -> None:
    rel = path.relative_to(ROOT).as_posix()
    if not isinstance(g, dict):
        p.error(rel, "top level must be an object")
        return
    for key in ("id", "title", "steps"):
        if key not in g:
            p.error(rel, f"missing '{key}'")
    for key in g:
        if key not in GUIDE_KEYS:
            p.warn(rel, f"unknown guide field '{key}'")
    check_tokens(p, rel, g.get("races"), RACES, "races")
    check_tokens(p, rel, g.get("classes"), CLASSES, "classes")
    lo, hi = g.get("minLevel", 1), g.get("maxLevel", 60)
    if not (isinstance(lo, int) and isinstance(hi, int) and 1 <= lo <= hi <= 60):
        p.error(rel, "minLevel/maxLevel must be integers with 1 <= min <= max <= 60")
    if g.get("zone") and g["zone"] not in zones:
        p.error(rel, f"unknown zone '{g['zone']}' (add it to guides/zones.json)")

    steps = g.get("steps")
    if not isinstance(steps, list) or not steps:
        p.error(rel, "'steps' must be a non-empty list")
        return
    zone = g.get("zone")
    for i, s in enumerate(steps, 1):
        where = f"{rel} step {i}"
        if not isinstance(s, dict):
            p.error(where, "step must be an object")
            continue
        for key in s:
            if key not in STEP_KEYS:
                p.warn(where, f"unknown step field '{key}'")
        action = s.get("action")
        if action not in ACTIONS:
            p.error(where, f"unknown action '{action}'")
            continue
        if action in QUEST_ACTIONS and not (s.get("quest") or s.get("questId")):
            p.error(where, f"'{action}' needs 'quest' or 'questId'")
        if action == "level" and not isinstance(s.get("level"), int):
            p.error(where, "'level' step needs an integer 'level'")
        if action == "note" and not s.get("text"):
            p.error(where, "'note' step needs 'text'")
        if "questId" in s and not (isinstance(s["questId"], int) and s["questId"] > 0):
            p.error(where, "'questId' must be a positive integer")
        if "objective" in s and not (isinstance(s["objective"], int) and s["objective"] > 0):
            p.error(where, "'objective' must be a positive integer")
        if s.get("zone"):
            zone = s["zone"]
            if zone not in zones:
                p.error(where, f"unknown zone '{zone}' (add it to guides/zones.json)")
        has_x, has_y = "x" in s, "y" in s
        if has_x != has_y:
            p.error(where, "'x' and 'y' must be given together")
        if has_x and has_y:
            for axis in ("x", "y"):
                v = s[axis]
                if not isinstance(v, (int, float)) or not 0 <= v <= 100:
                    p.error(where, f"'{axis}' must be a number from 0 to 100")
            if not zone:
                p.error(where, "coordinates without a zone (set 'zone' on the step or guide)")
        check_tokens(p, where, s.get("classes"), CLASSES, "classes")
        check_tokens(p, where, s.get("races"), RACES, "races")


def lua_long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    return f"[{eq}[{text}]{eq}]"


def write_lua(path: Path, register: str, payload: str, source: str) -> None:
    body = (
        f"-- Generated by tools/build_guides.py from {source}. Do not edit; edit the JSON.\n"
        "local _, ns = ...\n"
        f"ns.WH:{register}({lua_long_string(payload)})\n"
    )
    path.write_text(body, encoding="utf-8", newline="\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="validate only, write nothing")
    ap.add_argument("--install", metavar="ADDONS_DIR", help="copy the built addon into this AddOns folder")
    args = ap.parse_args()

    p = Problems()
    zones_path = GUIDES_DIR / "zones.json"
    zones = json.loads(zones_path.read_text(encoding="utf-8"))["zones"]

    guides: list[tuple[Path, dict]] = []
    ids: dict[str, Path] = {}
    for path in sorted(GUIDES_DIR.rglob("*.json")):
        if path == zones_path or path.name.endswith(".schema.json"):
            continue
        try:
            g = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            p.error(path.relative_to(ROOT).as_posix(), f"invalid JSON: {e}")
            continue
        validate_guide(p, path, g, zones)
        gid = g.get("id") if isinstance(g, dict) else None
        if isinstance(gid, str):
            if gid in ids:
                p.error(path.name, f"duplicate id '{gid}' (also in {ids[gid].name})")
            ids[gid] = path
        guides.append((path, g))

    for path, g in guides:
        nxt = g.get("next") if isinstance(g, dict) else None
        if nxt and nxt not in ids:
            p.error(path.name, f"'next' points to unknown guide '{nxt}'")

    for line in p.warnings + p.errors:
        print(line)
    steps = sum(len(g.get("steps", [])) for _, g in guides if isinstance(g, dict))
    print(f"{len(guides)} guides, {steps} steps, {len(p.errors)} errors, {len(p.warnings)} warnings")
    if p.errors:
        return 1
    if args.check:
        return 0

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for old in OUT_DIR.glob("*.lua"):
        old.unlink()
    files = ["Zones.lua"]
    write_lua(OUT_DIR / "Zones.lua", "RegisterZonesJSON",
              json.dumps({"zones": zones}, ensure_ascii=False, separators=(",", ":")),
              "guides/zones.json")
    for path, g in sorted(guides, key=lambda t: (t[1].get("minLevel", 1), t[1]["id"])):
        name = f"{g['id']}.lua"
        write_lua(OUT_DIR / name, "RegisterGuideJSON",
                  json.dumps(g, ensure_ascii=False, separators=(",", ":")),
                  path.relative_to(ROOT).as_posix())
        files.append(name)
    xml = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">']
    xml += [f'  <Script file="{f}"/>' for f in files]
    xml.append("</Ui>")
    (OUT_DIR / "Guides.xml").write_text("\n".join(xml) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {len(files)} files to {OUT_DIR.relative_to(ROOT).as_posix()}")

    if args.install:
        dest_root = Path(args.install)
        if not dest_root.is_dir():
            print(f"AddOns folder not found: {dest_root}")
            return 1
        dest = dest_root / "WoWHelper"
        if dest.exists():
            shutil.rmtree(dest)
        shutil.copytree(ADDON_DIR, dest)
        print(f"Installed to {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
