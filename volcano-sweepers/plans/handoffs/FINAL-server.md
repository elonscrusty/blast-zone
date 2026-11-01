# FINAL handoff: server + shared audit
1. Auto-Sweep is ON for new players (`ProfileSchema.default().settings.autoSweep = true`); old saves keep their value.
2. Lava: the server only drops the ball (`BombVisuals`); ring + splash are client-only at `bomb.radius`.
3. `VSSweeping` is re-set on a new body after a respawn mid-sweep (SweepService compares the attribute).
4. Co-op supply: `ProgressRules.PACE_SHARE_PER_EXTRA = 0.45` (2+ kids get the 0.95 feed); duo coins ~2x better in pacing.test.
5. GeyserService forgets old gem ids when none are live (no slow growth on long servers).
6. World rescue (body inside the volcano) tells MoveWatch it was a server move.
7. Verified: require paths, tags, remote payloads, VSTool/VSSweeping names, MoveWatch honest-play cases, profile retry loop.
8. Tests: profile (autoSweep default), progress_rules (duo pace share). 523 passed; stylua clean; rojo builds.
9. Needs Play: bounce feel, one-ring look, snap-back never on honest phones, first Studio boot (string requires).
10. Full report and tap-through checklist: plans/audit/FINAL-server.md.
