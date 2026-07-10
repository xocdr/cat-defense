# Cat Defense — AGENTS.md

Godot 4.7 Mobile project with no package manager, build system, or test suite. Open `project.godot` in the editor and press Play.

## Run / verify

- **Run**: open `project.godot` in Godot 4.7, press Play (entry: `scenes/LoadingScreen.tscn`)
- **No CLI commands exist** — no `npm`, `make`, `pytest`, linter, or typechecker. Do not invent any.
- Visual verification: `_shot_lobby.gd` / `_ShotLobby.tscn` and `_shot_test.gd` / `_ShotTest.tscn` are **temporary screenshot harnesses**, not test files. Delete after one-off use.

## Scene flow

```
LoadingScreen.tscn  ──(background preload)──>  Lobby.tscn  ──(pick level)──>  Main.tscn
```

- `LoadingScreen.tscn` uses `ResourceLoader.load_threaded_request` for the Lobby scene
- `Lobby.tscn` (`lobby.gd`) has 4 pages: level-select map, Cat Upgrades, Extra (consumables), Shop
- `Main.tscn` (`main.gd`) owns the tower-defense match loop

## Architecture

### Autoload singleton

`GameState` (`game_state.gd`) is the **only autoload** (`*res://scripts/game_state.gd`). Persists to `user://savegame.cfg` (Godot ConfigFile). Holds gems, unlocked levels, items, cat upgrades, settings, daily streak. Everything else is in-scene state.

### Economy split

| Context | Currency | Persistence |
|---------|----------|-------------|
| Lobby / meta-game | **gems** (`GameState.gems`) | Saved to `savegame.cfg` |
| Match (`Main.tscn`) | **coins** (`main.gd.coins`) | Per-match only, no save |

The two are **not connected**. No shared save/economy system.

### Merge-board defense (main.gd)

- 5 rows × 2 columns grid (`ROW_Y`, `SLOT_COL_X` in main.gd)
- Tap Buy → places a level-1 Cat in a random empty slot
- **Merge**: drag a cat onto a same-level cat → combines into level+1
- **Trash slot** (row 4, col 0): drag a cat there for a partial refund
- Every **4 merge levels** → next character tier (C1 through C15)
- 10 waves to win (`WIN_WAVE`); wave 5 and 10 spawn a boss
- Pause/unpause via `get_tree().paused = true/false`

### Actors — group-based discovery (no central registry)

- Cats (`cat.gd`, `class_name Cat`) join group `"cats"`, scan `"enemies"` group each frame for nearest same-row target
- Enemies (`enemy.gd`, `class_name Enemy`) join group `"enemies"`, find blockers via `"blockers"` group
- **No physics bodies or collision shapes** — all detection is distance checks + node group queries in `_process`
- Bullets (`bullet.gd`) home toward their target node reference, no collision

### AnimUtil — runtime SpriteFrames

`AnimUtil.cached_frames()` builds `SpriteFrames` at runtime by listing PNG files from `Png/` subdirectories. Uses a static dictionary cache so all actors of the same type share frames. Never use pre-baked `.tres` SpriteFrames — always go through AnimUtil.

### Items (consumables)

Three items, routed through `GameState.items`:

| ID | Class | File |
|----|-------|------|
| `spikes` | `SpikeTrap` | `spike_trap.gd` |
| `tnt` | instant AOE | `main.gd` `_try_place_item` |
| `boxer` | `BoxingCat` | `boxing_cat.gd` |

Items must be purchased in lobby (gems) before use in match.

### Shop placeholder

`shop_panel.gd` — every "purchase" immediately emits `item_purchased(gems)` with no payment backend. Preserve this signal contract if wiring real IAP/ad rewards.

## Asset conventions

Five parallel trees — naming must stay consistent across all:

| Directory | Format | Purpose |
|-----------|--------|---------|
| `Ai/` | Adobe Illustrator | Source art |
| `Eps/` | EPS | Vector exports |
| `Png/` | PNG | Runtime sprites (consumed by AnimUtil) |
| `Json Atlas/` | Atlas+JSON+PNG triplets | Spine skeletal animation (not wired in-game) |
| `Spine/` | .spine project files | Spine editor sources |

### Adding a new character/enemy

1. Add matching folders in all 5 tree locations
2. Update `Png/Characters/C%d/` for cats, or `Png/Enemies/Enemy Reg %d` / `Enemy Boss %d` for enemies
3. In `main.gd` `_spawn_enemy()`: adjust `enemy_index` range (Reg: 1-8, Boss: 1-7)
4. Cat character bands are derived from merge level: `character_index = floor((level - 1) / 4) + 1`

### Spine atlas triplets

`Json Atlas/*/*.atlas` + `.json` + `.png` are matched sets. Never edit one file without checking the other two. These are **not currently used** by gameplay code (AnimUtil reads loose PNGs instead).

## Cat appearance / character tiers

`cat.gd` uses `Png/Characters/C%d/Idle` and `C%d/Shoot` (1 ≤ %d ≤ 15). Character advances every 4 merge levels. A badge chevron (`Up0`–`Up3` from `Png/Ui/`) shows the step within the current band.

## Enemy appearance

Regular enemies: `Png/Enemies/Enemy Reg %d/Walk`, `Attack`, `Dead` (%d = 1-8)
Boss enemies: `Png/Enemies/Enemy Boss %d/Walk`, `Attack`, `Dead` (%d = 1-7)
Path pattern is chosen in `enemy.gd:_ready()` based on `is_boss`.

## Screen / rendering

- 1280×720 viewport, `canvas_items` stretch mode, `expand` aspect
- Mobile renderer, D3D12 on Windows

## Other scripts (quick reference)

| File | `class_name` | Role |
|------|-------------|------|
| `wall.gd` | `Wall` | Crate barricade HP bar + broken overlay |
| `fx.gd` | `Fx` | `explosion()`, `muzzle_flash()` one-shots |
| `float_text.gd` | `FloatText` | Rising damage number labels |
| `slot.gd` | `Slot` | Grid cell (occupancy, drag highlight) |
| `spike_trap.gd` | `SpikeTrap` | AOE pad on road |
| `boxing_cat.gd` | `BoxingCat` | Summoned blocker on road |
