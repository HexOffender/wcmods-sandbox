"""Pack the mods for a release: dist/sandbox-<version>.zip and dist/sandbox-welcome-<version>.zip, each with
the mod's folder at its top (the way wcmods adds a mod from a .zip). Each mod's folder name is its id, and
"sandbox" is the one other mods name in "requires".

    python tools/pack.py

It first checks that the example's copy of api/sandbox_api.lua is the same as api/'s.
"""
import filecmp
import json
import os
import sys
import zipfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODS = {"sandbox": os.path.join(HERE, "sandbox"),
        "sandbox-welcome": os.path.join(HERE, "examples", "sandbox-welcome")}
API = os.path.join(HERE, "api", "sandbox_api.lua")


def pack(mod_id, folder):
    with open(os.path.join(folder, "mod.json"), encoding="utf-8") as f:
        version = json.load(f)["version"]
    out = os.path.join(HERE, "dist", f"{mod_id}-{version}.zip")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for here, dirs, files in os.walk(folder):
            dirs.sort()
            for name in sorted(files):
                path = os.path.join(here, name)
                z.write(path, mod_id + "/" + os.path.relpath(path, folder).replace(os.sep, "/"))
    return out


def main():
    copy = os.path.join(MODS["sandbox-welcome"], "scripts", "sandbox_api.lua")
    if not filecmp.cmp(API, copy, shallow=False):
        sys.exit(f"{copy} isn't the same as {API}: copy it again")
    for mod_id, folder in MODS.items():
        print(pack(mod_id, folder))


if __name__ == "__main__":
    main()
