<!-- retired-notice:start -->
> **Retired experiment, kept for reference.** The living project is [kody-w/RAPP](https://github.com/kody-w/RAPP).
<!-- retired-notice:end -->

# Second Seat

<!-- rapp1:network-header:start -->
[![RAPP/1](https://kody-w.github.io/rapp-hive-public/portfolio/badges/second-seat.svg)](https://github.com/kody-w/rapp-hive-public/blob/main/portfolio/repos/second-seat.md) · **New to RAPP?** [Start here: get your Brainstem →](https://github.com/kody-w/rapp-installer#start-here)
<!-- rapp1:network-header:end -->

> A pilot flies this world through the same six controls you have. The others below look up.

**Live:** https://kody-w.github.io/second-seat/

A single-file RAPP front door. An autopilot flies a craft through five procedurally
built realms joined by portals; a director cuts between twenty-four shots; sixteen
agents work the ground of every realm and turn to look up when you come over them.
Take the stick whenever you like — the pilot writes into the *same six controls*
your keyboard writes into, so it can never do anything you can't.

- **Drag** on the stage to look around. Dragging takes the **camera**, not the stick.
- **W A S D · Space · Shift** fly. Touching any of them takes the stick; let go and
  the pilot resumes from the nearest waypoint.
- **Record** composites titles, a lower third and a timecode into the frame *as it
  runs*, so the `.webm` is already cut when the flight ends.

## Auth

Same front door as [`kody-w/heimdall`](https://github.com/kody-w/heimdall): GitHub
OAuth **device-code** flow through the estate auth worker, token stored under the
shared `rapp_settings` key. Because every front door on `kody-w.github.io` shares
one origin, signing in here signs you in at Heimdall and vice versa.

## Memory

The logbook is not a saved blob — it is an append-only **rapp/1 frame chain** in
`localStorage`. Every boot, waypoint, portal, handoff, sighting, sign-in and saved
take appends an eleven-key frame (SPEC.md §7) carrying its own particle and wave
hash and linked to its predecessor. The panel you see is a *projection*: replay the
frames and the numbers come back. Identity is a rappid minted once from UUIDv4
entropy — never a name hash.

Anchored to `rapp/1` rev-6 (pinned snapshot; the page cannot fetch the anchor at
runtime, so the revision and spec hash are carried inline to be checked against
[the live anchor](https://raw.githubusercontent.com/kody-w/rapp-1/main/anchor/orient.json)).

## Taking it to Roblox

The world is defined as data, not as code: [`world.json`](./world.json). It carries
every number the browser build actually runs — realms and palettes, the skyline
generator, waypoints, the portal, the crowd, the flight model, the director's
24-shot list and its cadence.

`check-world.py` reads those numbers back out of the page and **fails if they
disagree**, so the spec cannot quietly rot into fiction.

[`roblox/WorldImporter.luau`](./roblox/WorldImporter.luau) rebuilds the same world in
Studio from that file. It is not a translation of the browser code — it re-derives
the world by running the same seeded LCG in the same consumption order. That claim
is checkable: `world.json` ships a **parity vector** of the first eight draws from
seed 7, and an engine that cannot reproduce them is building a different world
wearing the same names.

```lua
local Importer = require(script.WorldImporter)
Importer.build(1)      -- one realm
Importer.buildAll()    -- all five, laid out side by side
```

What deliberately does **not** port is named in `does_not_port`: the `.webm`
recording, the localStorage frame chain, and the GitHub device-code sign-in. Each
needs a Roblox-native answer (its own capture, a DataStore, the player identity
Roblox already has) rather than a translation — and moving the chain to a DataStore
changes its trust model from "the player's own browser-local record" to
"server-authoritative", which is a real decision, not a detail.
