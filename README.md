# Second Seat

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
