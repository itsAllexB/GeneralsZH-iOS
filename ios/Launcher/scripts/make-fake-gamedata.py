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

# Writes a tiny fake Zero Hour game-data folder (well-formed .big archives with the entries the
# launcher checks, a few bytes each) and fake engine logs, to exercise the launcher's validation
# and log viewer without the real 2.7 GB of data.
#
#   python3 -I scripts/make-fake-gamedata.py <gamedata-dir|-> [--broken] [--logs <documents-dir>]
#                                            [--support <GameSupport-dir>]
#
# "-" as the game data dir writes no game data (only --logs / --support).
# --retail leaves out the port's DefaultOptions.ini, like a real game folder.
# --support writes a fake <App>/GameSupport: fonts/, Window/Menus/*.wnd, dxvk.conf, DefaultOptions.ini.
#
# --broken makes the copy incomplete: INIZH.big/INI.big without Weather.ini, an empty
# SpeechZH.big and a Music.big with a bad header.
import os, struct, sys, datetime

def big(entries):
    names = [e.encode() + b"\0" for e in entries]
    header = 16 + sum(8 + len(n) for n in names)
    table, payload, offset = b"", b"", header
    for i, n in enumerate(names):
        body = b"fake payload %d\n" % i
        table += struct.pack(">II", offset, len(body)) + n
        payload += body
        offset += len(body)
    return b"BIGF" + struct.pack("<I", header + len(payload)) + struct.pack(">II", len(entries), header) + table + payload

def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)

def main():
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__ or "usage: make-fake-gamedata.py <dir> [--broken] [--logs <docs>]")
    root, broken = args[0], "--broken" in args
    if "--support" in args:
        support = args[args.index("--support") + 1]
        write(f"{support}/fonts/GXFakeFont.ttf", b"fake font\n")
        write(f"{support}/Window/Menus/MainMenu.wnd", b"; fake window layout override\n")
        write(f"{support}/dxvk.conf", b"dxvk.logLevel = none\n")
        write(f"{support}/DefaultOptions.ini",
              b"IdealStaticGameLOD = High\nStaticGameLOD = High\nTextureReduction = 0\nHeatEffects = yes\nDynamicLOD = no\n")
        print(f"fake GameSupport in {support}")
    if root != "-":
        make_game(root, broken, retail="--retail" in args)
    if "--logs" in args:
        make_logs(args[args.index("--logs") + 1], root)

def make_game(root, broken, retail=False):
    weather = [] if broken else ["Data\\INI\\Default\\Weather.ini"]
    write(f"{root}/INIZH.big", big(["Data\\INI\\GameData.ini", "Data\\INI\\AIData.ini"] + weather))
    for name in ["AudioZH.big", "EnglishZH.big", "MapsZH.big", "MusicZH.big", "TexturesZH.big",
                 "W3DZH.big", "WindowZH.big", "TerrainZH.big", "ShadersZH.big", "PatchZH.big"]:
        write(f"{root}/{name}", big([f"Data\\{name}.dat"]))
    write(f"{root}/SpeechZH.big", b"" if broken else big(["Data\\Audio\\Speech\\x.wav"]))
    base = f"{root}/ZH_Generals"
    write(f"{base}/INI.big", big(["Data\\INI\\GameData.ini"] + weather))
    for name in ["Terrain.big", "Textures.big", "W3D.big", "Window.big", "shaders.big", "Audio.big",
                 "Speech.big", "maps.big", "English.big"]:
        write(f"{base}/{name}", big([f"Data\\{name}.dat"]))
    write(f"{base}/Music.big", b"NOT A BIG ARCHIVE" if broken else big(["Data\\Audio\\Tracks\\x.mp3"]))
    if not retail:  # a developer GameData carries the port's files; a retail folder does not
        write(f"{root}/DefaultOptions.ini",
              b"IdealStaticGameLOD = High\nStaticGameLOD = High\nTextureReduction = 0\nHeatEffects = yes\nDynamicLOD = no\n")
    print(("broken" if broken else "valid") + f" fake game data in {root}")

def make_logs(docs, root):
    now = datetime.datetime.now().strftime("%H:%M:%S")
    lines = [f"INFO: iOS working directory (bundle): {root}",
             "INFO: Seeded default Options.ini",
             "INFO: Initializing SDL3 video subsystem...",
             "INFO: Creating SDL3 Vulkan window...",
             "INFO: iOS internal resolution set to 2868x1320 (window 2868x1320)"]
    lines += [f"[GX-Perf] {now} frame {i}: logic 2.1 ms, render 9.8 ms, audio 0.4 ms" for i in range(400)]
    lines += ["WARNING: texture 'trdirtroad' not found, using placeholder",
              "ERROR: example error line for the search test", "INFO: GameMain() returned with code 0"]
    write(f"{docs}/generals-stderr.log", ("\n".join(lines) + "\n").encode())
    write(f"{docs}/generals-stderr-prev.log",
          b"INFO: previous session\nFATAL: example crash line in the previous session\n")
    print(f"fake logs in {docs}")

if __name__ == "__main__":
    main()
