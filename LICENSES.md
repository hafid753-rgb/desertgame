# Third-party license manifest

Every file not written for Hafid must be listed here before it is committed.
Rule: no Nintendo-derived code, data or ROM content, ever (see docs/adr/0002-no-decomp-code.md).

| Component | Version | License | Where | Notes |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.6.3-stable | MIT | engine (not vendored) | https://godotengine.org/license |
| Jolt Physics (built into Godot) | engine module | MIT | engine | |
| Godot fallback font | bundled with engine | OFL / engine license | used by HUD via ThemeDB | Replace with an Arabic+Latin font (e.g. Noto Sans Arabic, OFL) before localisation |

All code under `game/`, `tests/`, `tools/` and all placeholder geometry are original to this project.
Planned addons (Phantom Camera MIT, LimboAI MIT, netfox MIT) are **not yet included**; add a row when vendored.
