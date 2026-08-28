#!/usr/bin/env python3
"""build-site.py — one source, two builds.

second-seat.html is the shared body (published as-is as a Claude Artifact).
This script wraps it as a standalone GitHub Pages page and appends Heimdall's
auth block. Run it after ANY edit to second-seat.html so the artifact and the
front door cannot drift apart.
"""
import re, sys, pathlib
here = pathlib.Path(__file__).parent
body = (here / "second-seat.html").read_text()
auth = (here / "auth-block.js").read_text()

body = body.replace('      <button class="btn" id="recBtn">',
 '''      <button class="btn" id="authBtn">Sign in with GitHub</button>
      <a class="btn" id="authLink" hidden target="_blank" rel="noopener noreferrer">Enter the code at github.com/login/device</a>
      <span class="chip" id="who" hidden></span>
      <button class="btn" id="recBtn">''', 1)

# the sign-in link is a button-shaped anchor; give it the anchor reset it needs
body = body.replace("</style>",
 """#authLink{text-decoration:none;border-color:var(--teal);color:var(--teal-ink)}
#authLink:hover{border-color:var(--teal)}
</style>""", 1)

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="Second Seat — a pilot flies a world through the same controls you have, and the others below look up.">
<style>:root{{color-scheme:light dark}}body{{margin:0}}[hidden]{{display:none!important}}</style>
</head>
<body>
{body}
<script>
{auth}
</script>
</body>
</html>
"""
out = here / "secondseat-site" / "index.html"
out.write_text(html)
print(f"built {out} ({len(html)} bytes)")
