"""Run Sandbox mode's tests: every Lua file must load (a syntax check), then tests/story_spec.lua drives
sandbox/scripts/story.lua with the game stubbed. They need Lua 5.4, the version UE4SS embeds: `lua5.4` or a
`lua` that says 5.4 on the PATH. Without one they're skipped, saying so; CI installs it.

    python tests/run.py
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FOLDERS = ("sandbox", "api", "examples", "tests")


def find_lua():
    for name in ("lua5.4", "lua54", "lua"):
        path = shutil.which(name)
        if path:
            said = subprocess.run([path, "-v"], capture_output=True, text=True)
            if "5.4" in said.stdout + said.stderr:
                return path
    return None


def main():
    lua = find_lua()
    if not lua:
        # CI sets REQUIRE_LUA=1: a Lua that went missing fails there rather than skipping to a green run.
        print("skipped: no Lua 5.4 on the PATH (lua5.4, or a lua that is 5.4); CI runs these")
        return 1 if os.environ.get("REQUIRE_LUA") == "1" else 0
    bad = 0
    for folder in FOLDERS:
        for here, dirs, files in os.walk(os.path.join(ROOT, folder)):
            dirs.sort()
            for name in sorted(files):
                if name.endswith(".lua"):
                    path = os.path.join(here, name)
                    check = subprocess.run([lua, "-e", f"assert(loadfile({path!r}))"], capture_output=True, text=True)
                    if check.returncode:
                        bad += 1
                        print(f"FAIL  {os.path.relpath(path, ROOT)} doesn't load: {check.stderr.strip()}")
    if bad:
        return 1
    print("ok    every Lua file loads")
    return subprocess.run([lua, os.path.join(HERE, "story_spec.lua")]).returncode


if __name__ == "__main__":
    sys.exit(main())
