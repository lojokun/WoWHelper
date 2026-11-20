#!/usr/bin/env python3
"""Run WoWHelper's Lua code against a mocked WoW API.

Needs the `lupa` package (pip install lupa), which bundles a Lua 5.1 runtime.
Loads the addon files in .toc order (expanding Guides.xml), then runs
tools/test/scenario.lua.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import lupa.lua51 as lua51

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "addon" / "WoWHelper"
HERE = Path(__file__).resolve().parent


def addon_files() -> list[Path]:
    files: list[Path] = []
    for line in (ADDON / "WoWHelper.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        path = ADDON / line.replace("\\", "/")
        if path.suffix == ".xml":
            for name in re.findall(r'file="([^"]+)"', path.read_text(encoding="utf-8")):
                files.append(path.parent / name)
        else:
            files.append(path)
    return files


def main() -> int:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((HERE / "wow_mock.lua").read_text(encoding="utf-8"))
    lua.execute("ADDON_NS = {}")
    loader = lua.eval(
        "function(src, name) local f, e = loadstring(src, name) if not f then error(e) end"
        " f('WoWHelper', ADDON_NS) end"
    )
    for path in addon_files():
        loader(path.read_text(encoding="utf-8"), "@" + path.relative_to(ROOT).as_posix())
    failed = lua.execute((HERE / "scenario.lua").read_text(encoding="utf-8"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
