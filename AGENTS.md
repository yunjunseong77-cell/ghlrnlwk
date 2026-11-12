# Project context

This is “훈련병장 회귀자는 전역하고 싶어”, a Korean native Windows game made with Godot 4.7.2 stable (GL Compatibility, 1280×720). Keep it a native game; do not replace it with a website, browser app, or Sites project. Source files are UTF-8; use `Get-Content -Encoding UTF8` in Windows PowerShell.

Before substantial changes, read `docs/개발 인수인계.txt`, `시작 안내.txt`, `docs/게임 진행안.txt`, and the relevant code. `docs/훈련과PX안내.txt` explains the training/economy contracts. The handoff distinguishes implemented gameplay from future plans. Follow newer user instructions over these notes.

## Design commitments

- Build enjoyable, tactile gameplay with clear feedback and meaningful choices. Passing automated checks alone does not establish visual quality or fun; run and inspect the native game.
- The user rejected the repetitive 14-command drill minigame. It is retired and replaced by a short story event. Do not restore it as required progression or an active replay entry.
- The approved direction is top-down 2D exploration and a growing military/regressor RPG. Actual enemy combat, active skills, later training, Sangmudae, and the 8th Division chapters are not implemented yet.
- Preserve the user's established story, character names, dialogue tone, and supplied music. Real military schedules and historical details that are still unverified must not become asserted facts.
- Equipment must fit each facing and walk pose. Reuse `soldier_appearance.gd` for world and portrait rendering; do not paste shop thumbnails onto the character.
- Consumables are manually used HP/SP recovery items. Never spend them automatically when a training game starts, fails, is cancelled, or is replayed.

## State and regression safeguards

- Reuse `training_progress.gd` for gear, items, currency, rewards, and vitals. Keep effect application and inventory deduction atomic; failed saves must not grant rewards or consume items.
- Account replay achievements and campaign completion are separate. Home quick-play must not skip campaign quests. A new story resets campaign/location while retaining account coins, gear, inventory, and replay records; first-clear bonuses pay only once.
- Preserve legacy saves and schema migrations, including old prepared items becoming quick-slot assignments without quantity loss. Do not convert a retired drill clear into a shooting clear.
- Training uses `begin_run` → `activate_run` on actual start → `finish_run` once, or `cancel_run`. Entry screens do not start timers or grant rewards. Preserve the origin location when returning from camp training.
- Preview mode must not mutate actual player state. Tests must use isolated temporary save paths, never real `user://` saves.
- Keep the Windows native nickname dialog and verify multi-syllable Korean input. Do not reintroduce per-frame edits that overwrite IME composition.
- Keep reveille limited to 11 seconds. Preserve hiding underlying title/dialogue controls during training so they cannot intercept shooting clicks.

## Validation and repository hygiene

- Import assets with the installed Godot console executable: `--headless --editor --path . --import`. `tools/run_checks.ps1` handles import and test selection (`-Suite all` includes native GUI checks).
- Run relevant tests under `tools/`. `verify_training.gd` and `verify_vitals.gd` can run headless; GUI/input/rendering checks must use a native window and run sequentially. See the handoff for commands and scope.
- Inspect affected 1280×720 layouts, directional equipment poses, and real interactions. Create `docs/previews` before screenshot checks if absent. Do not invent test results.
- Preserve asset source/license records. Do not commit `.godot`, exported builds, private saves, credentials, or machine-local generated-image folders. Required game assets belong in the repository using relative `res://` paths.
- This repository has no implied blanket open-source license. Do not add one without user direction.
