# 20 First-time intro, save messages, release checklist
- Done: "How to play" intro (carter's pick C, Four Tiles): move, aim, fire, slide, one GOT IT, Skip. Shows once, in the lobby only (phase Waiting), words follow the device (phone, keyboard, controller) and read the real slide key and cooldown.
- Done: "Saving is off" strip (carter's pick A, Top Strip) with TRY AGAIN. Slow load shows a gold "Still loading your save..." strip; a lost save says to rejoin. Hidden during a match so the HUD keeps the top of the screen.
- Code: `src/client/Onboarding/` (pure: IntroSteps, DataNotice, OnboardingModel; views: IntroView, StatusStripView; wiring: OnboardingClientSystem). Numbers: `Config.Onboarding`. No server code: the server rules are piece 17's.
- Uses piece 17 (PR #15): `ProfileStatus` in, `ProfileStatusRequest`, `RetryProfileLoadRequest`, `SetFlagRequest("introSeen", true)` out. If those remotes are missing, the intro shows once per join and nothing is saved or shown as an error.
- Rules: flags from a failed or lost save are not trusted; the intro shows once, skippable, and writes nothing. TRY AGAIN waits 5 s between taps. Done and Skip both count as seen.
- Tests: `tests/onboarding.test.luau` (14 checks: words, bindings, who sees the intro, failed/lost/slow states, retry wait, bad payloads). `lune run tests/run` 335 pass, stylua and rojo build pass.
- Not run: selene and a luau type check (no network for the Roblox API dump or luau-lsp here), nothing in Studio. How the tiles and strip look on a real phone is unseen.
- Release list: `plans/RELEASE-CHECKLIST.md` (manual 2-player scenarios from brief section 26, saving test, device targets, known limits). Update its limits after Phase 4 and 5 land.
- Left: tile pictures are drawn from flat shapes, not the 3D preview; no in-match hint if the intro was skipped; no analytics.
