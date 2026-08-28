#!/usr/bin/env python3
"""check-world.py — the drift gate between world.json and the browser build.

world.json claims to be the numbers the browser actually runs. That claim rots
the moment someone edits one and not the other, and a spec nobody checks is
worse than no spec because people trust it. So this reads the real values back
out of second-seat.html and fails if they disagree.

Run it after any edit to either file. Exit 0 = they agree.
"""
import json
import pathlib
import re
import sys

here = pathlib.Path(__file__).parent
src = (here / "second-seat.html").read_text()
world = json.loads((here / "secondseat-site" / "world.json").read_text())

fails = []


def check(label, expected, pattern, cast=float):
    """Pull one number out of the source and compare it to the spec."""
    m = re.search(pattern, src)
    if not m:
        fails.append(f"{label}: pattern not found in second-seat.html — {pattern}")
        return
    actual = cast(m.group(1))
    if actual != cast(expected):
        fails.append(f"{label}: world.json says {expected}, code says {actual}")


f = world["flight"]
check("flight.turn_rate_rad_s", f["turn_rate_rad_s"], r"heading \+= \(controls\.left - controls\.right\) \* ([\d.]+) \* dt")
check("flight.thrust", f["thrust"], r"controls\.boost \? [\d.]+ : ([\d.]+)\)")
check("flight.thrust_boost", f["thrust_boost"], r"controls\.boost \? ([\d.]+) :")
check("flight.climb", f["climb"], r"vel\.y \+= \(controls\.up \? ([\d.]+) :")
check("flight.gravity", f["gravity"], r"vel\.y \+= \(controls\.up \? [\d.]+ : (-[\d.]+)\)")
check("flight.drag_per_second", f["drag_per_second"], r"vel\.multiplyScalar\(Math\.pow\(([\d.]+), dt\)\)")
check("flight.floor_y", f["floor_y"], r"if \(craft\.position\.y < ([\d.]+)\)")
check("flight.handback_ms", f["handback_ms"], r"now - lastHuman > (\d+)")

check("crowd.count", world["crowd"]["count"], r"for \(var q = 0; q < (\d+); q\+\+\)", int)
check("crowd.see_range", world["crowd"]["see_range"], r"SEE_RANGE = (\d+)", int)
check("crowd.seen_frame_threshold", world["crowd"]["seen_frame_threshold"], r"n >= (\d+)", int)

check("skyline.count", world["skyline"]["count"], r"for \(var i = 0; i < (\d+); i\+\+\)", int)
check("skyline.radius_min", world["skyline"]["radius_min"], r"var a = rnd\(\) \* Math\.PI \* 2, r = (\d+) \+ rnd\(\)", int)

check("waypoints.count", world["waypoints"]["count"], r"var legs = (\d+)", int)
check("waypoints.radius_min", world["waypoints"]["radius_min"], r"var rad = (\d+) \+ rnd\(\)", int)
check("waypoints.arrival_distance", world["waypoints"]["arrival_distance"], r"if \(dist < (\d+)\)", int)

check("portal.travel_ms", world["portal"]["travel_ms"], r"TRAVEL_MS = (\d+)", int)
check("portal.cadence_ms_min", world["portal"]["cadence_ms_min"], r"now \+ (\d+) \+ Math\.random\(\) \* \d+;", int)

check("director.cut_ms_min", world["director"]["cut_ms_min"], r"shotUntil = now \+ \((\d+) \+", int)
check("director.free_look_hold_ms", world["director"]["free_look_hold_ms"], r"LOOK_HOLD = (\d+)", int)

check("rng.default_seed", world["rng"]["default_seed"], r"var seed = (\d+);", int)
check("rng.reseed_ms", world["rng"]["reseed_ms"], r"setInterval\(reseed, (\d+)\)", int)

# the realm table must match name-for-name and colour-for-colour
code_realms = re.findall(r"\{ name:'([^']+)',\s*sky:0x([0-9A-Fa-f]{6})", src)
spec_realms = [(r["name"], r["sky"].upper()) for r in world["realms"]]
if [(n, c.upper()) for n, c in code_realms] != spec_realms:
    fails.append(f"realms differ:\n  code: {code_realms}\n  spec: {spec_realms}")

# the director's shot list must match, in order
# a shot name may be single- OR double-quoted (Agent's Eye needs the latter)
_shot_re = re.compile(r"""\{ n:\s*(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')""")
code_shots = [a or b for a, b in _shot_re.findall(src)]
if code_shots != world["director"]["shots"]:
    missing = [s for s in world["director"]["shots"] if s not in code_shots]
    extra = [s for s in code_shots if s not in world["director"]["shots"]]
    fails.append(f"shot list differs — only in spec: {missing} · only in code: {extra}")

if fails:
    print("WORLD SPEC DRIFT — world.json does not describe what the code runs:\n")
    for x in fails:
        print("  ✗ " + x)
    sys.exit(1)

print(f"world.json agrees with second-seat.html "
      f"({len(world['realms'])} realms, {len(world['director']['shots'])} shots, "
      f"{len(fails)} disagreements)")
