# Playtest protocol — The Room

**Goal:** decide whether the touch combat is fun before building anything else.
**Pass gate (week 4):** at least 7 of 10 testers rate fun ≥ 4/5, fewer than 1 accidental special per minute, 30 FPS p95 on the low-tier phone.

## Setup

1. Three phones: low (3–4 GB RAM, Unisoc/Helio G3x), mid (Helio G85/G99, SD 680), high.
2. Install the APK, battery > 80%, phone cool, airplane mode on.
3. Testers have not seen the controls. Give them only the one-page control card (README table).

## Session (10 minutes per tester)

| Minute | What happens | Observer notes |
| --- | --- | --- |
| 0–2 | Free play, no help | Which buttons do they find? What do they try first? |
| 2–5 | Fight the jinn | Count deaths, parries, perfect dodges (shown on screen) |
| 5–8 | Ask them to use Special (charge + attack, charge + dodge) | Count accidental specials and "I didn't mean that" moments |
| 8–10 | Switch to Fennec, then Lizard | Do they feel the stamina/speed difference? |

## Questions after (1–5 scale)

1. How fun was fighting the jinn?
2. Did the character do what you meant?
3. Could you tell which attack the jinn was about to do?
4. Were the buttons in comfortable places?
5. Would you play this for 30 minutes if there were more to do?
6. Open: what was most frustrating? What felt best?

## Record

```csv
date,tester,age,phone_model,phone_tier,minutes,fun_1to5,control_1to5,read_jinn_1to5,buttons_1to5,would_play_1to5,deaths,parries,perfect_dodges,accidental_specials,fps_p95_ms,frustration,best_moment
```

Pull `perf_*.csv` from the phone after each session (Android Studio device explorer or `adb exec-out run-as dev.overcode.hafid cat files/perf_<stamp>.csv`).
