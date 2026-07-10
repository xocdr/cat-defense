# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository nature

This is a **Godot 4.7 (Mobile) game project**, "Merge Cats Defender" (project name "Cat Defense") — a merge-and-defend game built on top of a large game art asset pack (originally a CraftPix art pack; see `Ai/`, `Eps/`, `Png/`, `Json Atlas/`, `Spine/`). The target UI/gameplay design is documented by the mockups in `Preview/Ui/*.png` and `samples/` — treat those images as the design spec. There is no external build system, package manifest, or test suite — the project is opened and run directly in the Godot editor. Do not invent npm/make/pytest-style commands.

- Run the game: open `project.godot` in the Godot 4.7 editor and press Play (main scene is `scenes/LoadingScreen.tscn`, set via `run/main_scene` in `project.godot`).
- Headless validation that works: `Godot_*.exe --headless --path . --import` (rebuilds the global class cache after adding `class_name` scripts — required before `--check-only`), then `--headless --path . res://scenes/Main.tscn --quit-after N` to boot a scene and watch stderr. `--check-only --script` cannot resolve the `GameState` autoload; that is expected, not a bug.
- No linter or automated test suite exists.

## Architecture

Flow: `LoadingScreen.tscn` (`scripts/loading_screen.gd`) preloads `Lobby.tscn` in the background behind a "Tap To Play" title screen → `Lobby.tscn` (`scripts/lobby.gd`) is the hub (level-select map, cat Upgrades, Extra consumables, gem Shop) → picking a level sets `GameState.selected_level` and loads `Main.tscn` (`scripts/main.gd`), the match scene.

**GameState** (`scripts/game_state.gd`) is an **autoload singleton** (registered in `project.godot`) holding all persistent state: gems, level unlock/completion, consumable item counts, per-character upgrade pips, best-ever merge level, settings toggles, and the daily-gift streak. It saves to `user://savegame.cfg` (ConfigFile) on every mutation. Lobby and Main both read/write only through its API (`add_gems`, `buy_item`, `use_item`, `upgrade_cat`, `complete_level`, `record_merge_level`, `claim_daily`, ...). In-match coins are NOT persistent — they live in `main.gd` for the duration of one match.

**Main.tscn / main.gd** owns the match loop (merge-defense):
- A 5-row × 2-col grid of `Slot.tscn` (`ROW_Y`/`SLOT_COL_X`, derived from the slot squares baked into the `Png/Area/Area*.png` backgrounds; row 4 col 0 is the trash cell, also baked into the art). The Buy button spawns a cat of `buy_level()` (rises with the best merge level this match) into a random free slot at an escalating coin cost.
- **Drag & drop** is handled centrally in `main.gd` (`_on_press`/`_on_release` from `_unhandled_input`, plus `_input` for motion/release while dragging so drops over UI buttons still resolve): drop on an equal-level cat → merge (level+1), on another cat → swap, on an empty slot → move, on the trash cell → sell. `Main`'s root runs `process_mode = 3` (ALWAYS) so pause input works while `get_tree().paused`; its gameplay children (`Wall`, `Slots`, `World`) are explicitly `process_mode = 1` (PAUSABLE). Any code path that pauses or ends the match must call `_cancel_drag()`.
- **Wall** (`scripts/wall.gd`, node in `Main.tscn`): the crate barricade and its HP-bar frame are baked into every Area background at fixed pixel positions; `wall.gd` only overlays the dynamic parts (draining fill ColorRects, dark crates region when broken) using the `BG_SCALE` (0.598, 0.678) screen mapping. Enemies attack the wall at `WALL_STOP_X` (only within a band, so a repair doesn't re-block enemies already past it); when it breaks they walk on, and any enemy crossing `LOSE_X` loses the match. Repair costs scale with missing HP and wave.
- **Waves**: 10 per level, banner + `WaveBar` counter; every 5th wave spawns a boss (`Enemy Boss %d`, big HP/damage multipliers). Enemy stats scale with wave and level. Wave-clear → 2.2 s break timer (its lambda guards `is_instance_valid(self)` because SceneTreeTimers outlive scene reloads). Win → `GameState.complete_level()` (gems bonus, unlocks next level).
- **Items** (bottom-right buttons, counts from `GameState.items`): arm a button, then tap the road — spikes (`scripts/spike_trap.gd`, timed row DPS pad), TNT (instant `Fx.explosion` + radius damage), boxing cat (`scripts/boxing_cat.gd`, joins the `"blockers"` group so enemies stop and fight it; its lifetime counts down in `_process` so it freezes while paused).

**Cat** (`cat.gd`) and **Enemy** (`enemy.gd`) are the actors, matched by `row`:
- A cat's appearance is derived from its merge `level`: character folder `C1..C15` advances every 4 levels (`character_for_level`), and the badge shows `Up0..Up3` chevrons for the step within the band plus the level number. Damage is `8 * 1.32^(level-1)` times the character's permanent lobby-upgrade multiplier (`GameState.cat_damage_multiplier`). Cats prefer same-row targets, fall back to nearest, and are invulnerable (the wall is the only thing defending).
- Enemies walk left, stop to attack `"blockers"`-group nodes or the wall (both expose `take_damage`/`is_dead`), and emit `reached_end` past `LOSE_X`. Bosses use the `Enemy Boss %d` folders and a larger scale.
- Groups `"cats"` / `"enemies"` / `"blockers"` are the only registries. Death anims keep an enemy in the group until freed, so **every** group iteration must check `is_dead()`.

**AnimUtil** (`anim_util.gd`) builds `SpriteFrames` at runtime by listing PNGs under `Png/` and caches them per directory-set (`cached_frames`) so all actors of one kind share a single SpriteFrames. `list_pngs` also accepts `*.png.import`/`*.png.remap` entries and strips the suffix — **required for exported PCK/APK builds**, where the loose `.png` files don't exist; don't "simplify" that away. `Fx` (`fx.gd`) and `FloatText` (`float_text.gd`) are static helpers for one-shot effects (explosion, muzzle flash) and rising damage/coin numbers.

**Lobby** (`lobby.gd`): the level map buttons (`Level1..Level8` + `Label1..Label8`) get their texture/disabled state from GameState (orange = completed, green = next to play, locked otherwise). The Upgrades page grid (15 cat rows: portrait, "Level N" unlock label, `0Bar..5Bar` pips, gem-cost plus button, `LockedCatBox` when locked) is built at runtime under `UpgradesPage/UpgradeScroll/UpgradeGrid` — character *i* unlocks for upgrading once `max_merge_level` reaches `4*(i-1)+1`. When rebuilding container children, `remove_child` before `queue_free` to avoid a one-frame double layout. The Extra page sells the three consumables for gems. `shop_panel.gd` is still a placeholder — every "purchase" just emits `item_purchased(gems)` with no payment backend; preserve that signal contract if/when a real IAP/ad-reward system is wired in (lobby routes it into `GameState.add_gems`).

Gotchas that already bit once: connect autoload signals from scene scripts with **method** callables, not lambdas (lambdas outlive the freed scene and error on the next emit); `pressed.is_connected` must be checked against the **bound** callable; SceneTreeTimers must pass `process_always = false` (or count down in `_process`) to respect pause.

## Asset structure

Assets are organized in parallel by format, with matching subfolder/character names across trees:

- `Ai/` — Adobe Illustrator source files (`.ai`), organized into `AddOn Help/`, `Cat Characters/`, `Enemy Characters/`, `Other/`
- `Eps/` — EPS exports of the same artwork (`Cats/`, `Enemies/`, `Other/`)
- `Png/` — Rasterized PNG exports consumed directly by `AnimUtil` at runtime, split into per-character folders (e.g. `Characters/C1`..`C15` with `Idle`/`Shoot`, `Enemies/Enemy Boss 1`..`7` and `Enemy Reg 1`..`8` with `Walk`/`Attack`/`Dead`, `Cat Guardian/`, `CatBoxing/`, `Explosion/`, `ShootFx/`, `Bullets/`, `Area/` (5 interchangeable battlefield backgrounds sharing one slot/wall layout), `Ui/`)
- `Json Atlas/` — Spine/texture-atlas exports (`.atlas`, `.json`, `.png` triplets) for in-engine skeletal animation, organized per character/effect
- `Spine/` — Spine editor source project files (`.spine`) and their source `Images/`, matching the `Json Atlas/` exports
- `Preview/`, `samples/` — the design mockups the game UI is built to match

UI asset notes (`Png/Ui/`): `Up0..Up3` = merge chevrons, `0Bar..5Bar` = pip bars, `Uplogo1..15` = shield badges (NOT cat portraits — upgrade rows use `Characters/C%d/Idle/Character%d-Idle_00.png`), `AddonIcon6/7/8` = TNT/boxing-cat/spikes item icons, `BgPaused` is a wide toggle-row bar (don't stretch it into a panel). For `TextureRect`/`TextureButton`, remember stretch_mode 1 = TILE and 4 = left-anchored KEEP_ASPECT — wide button art usually wants 0 (scale).

When adding or modifying a character/enemy asset, keep naming and folder structure consistent across `Ai/`, `Eps/`, `Png/`, `Json Atlas/`, and `Spine/` — e.g. a new enemy called "Enemy Boss 8" would need matching entries in all five trees, and `main.gd`'s boss-index logic and `enemy.gd`'s `Png/Enemies/Enemy Reg %d` path convention would need updating to reference it.

## Working with Spine atlases

The `Json Atlas/*/*.atlas` + `.json` + `.png` triplets are matched sets — the `.json` references regions defined in the `.atlas`, which map onto the `.png` sprite sheet. Do not edit one file in a triplet without checking whether the other two need corresponding updates. Note the current in-game Cat/Enemy actors do NOT use these Spine atlases — they build `SpriteFrames` directly from loose PNGs via `AnimUtil` (see Architecture above); the Spine/Json Atlas assets appear to be for animations not yet wired into gameplay code.

## Key references

- Font used in the assets: Passion One (Google Fonts) — link in `Font Link.txt`. Not bundled in the repo; UI currently uses Godot's default font.
- Licensing: assets are from CraftPix; see `license.txt` (links to https://craftpix.net/file-licenses/) before reuse or redistribution.
