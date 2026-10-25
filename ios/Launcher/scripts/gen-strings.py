#!/usr/bin/env python3
# Command & Conquer Generals Zero Hour(tm)
# Copyright 2025 Electronic Arts Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Regenerates GXLauncher/Sources/GXLauncher/Resources/Localizable.xcstrings from every L("...")
# call in the launcher sources. English is the source language and the key; existing
# translations in the catalog are kept. Run: python3 -I scripts/gen-strings.py
import json, os, re, sys
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "GXLauncher", "Sources", "GXLauncher")
catalog_path = os.path.join(root, "Resources", "Localizable.xcstrings")
pattern = re.compile(r'\bL\(\s*"((?:[^"\\]|\\.)*)"')
keys = set()
for dirpath, _, files in os.walk(root):
    for name in files:
        if name.endswith(".swift"):
            with open(os.path.join(dirpath, name), encoding="utf-8") as f:
                for m in pattern.finditer(f.read()):
                    keys.add(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))
old = {}
if os.path.exists(catalog_path):
    with open(catalog_path, encoding="utf-8") as f:
        old = json.load(f).get("strings", {})
strings = {}
for key in sorted(keys):
    entry = old.get(key, {})
    entry["extractionState"] = "manual"
    locs = entry.setdefault("localizations", {})
    locs["en"] = {"stringUnit": {"state": "translated", "value": key}}
    strings[key] = entry
os.makedirs(os.path.dirname(catalog_path), exist_ok=True)
with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump({"sourceLanguage": "en", "strings": strings, "version": "1.0"}, f, indent=2, ensure_ascii=False, sort_keys=True)
    f.write("\n")
print(f"{len(strings)} strings -> {catalog_path}")
