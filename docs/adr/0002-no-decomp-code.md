# ADR 0002 — No decompiled or recompiled game code

**Status:** accepted, 2026-11-23

## Decision

No code, data tables, constants or assets derived from Nintendo or other commercial games
(zeldaret decomps, liboot, static recompilations, ROMs) may enter this repository, its build,
its servers or its app — not translated, not "rewritten by AI from the source", not temporarily.

Movement and combat are implemented from a behaviour spec written by playing games and
observing them, not by reading their code.

Any research comparing against decomp code lives in a separate private repository
(`hafid-research`) with no shared history.

## Why

liboot is AGPL-3.0 over vendored decompilation files that carry no license and require a
retail ROM; the BOTW decompilation has no license and lacks most traversal code.
Shipping derived code would put the whole game at legal risk.
