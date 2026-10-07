# MGEMod — Agent Guide

## Project Overview

MGEMod is a **1v1 and 2v2 duel training plugin for Team Fortress 2**, built on **SourceMod** and written in **SourcePawn**. It creates arena-based duel environments where players fight in realistic game situations (spire, badlands mid, granary last, etc.) with ELO rating, stats tracking, and multiple game modes.

This is a fork of [sappho's MGEMod](https://github.com/sapphonie/MGEMod) with significant additions: PostgreSQL support, 2v2 mode, per-map arena configs, API forwards/natives, ELO verification, and more.

Current version: **3.1.0-beta14**

## Architecture

### Compilation Unit

`mge.sp` is the **single compilation entry point**. It `#include`s all modules — there are no separately compiled plugins. Compile with:

```
spcomp -i"./addons/sourcemod/scripting/include/" addons/sourcemod/scripting/mge.sp -o ./addons/sourcemod/plugins/mge.smx
```

SourcePawn version: **1.12.x** (see `.github/workflows/build.yml`).

### Module Layout

```
addons/sourcemod/scripting/
├── mge.sp                    # Entry point, ConVars, lifecycle hooks
├── mge/
│   ├── globals.sp            # All global state: arrays, handles, enums
│   ├── arenas.sp             # Map config loading, spawn parsing, arena setup
│   ├── player.sp             # Player lifecycle, queue, damage hooks, menus
│   ├── match.sp              # Match flow, frag limits, round end, queue rotation
│   ├── sql.sp                # DB connection, driver detection, queries
│   ├── migrations.sp         # Schema migrations (SQLite/MySQL/PostgreSQL)
│   ├── hud.sp                # HUD text rendering (scores, timers, HP)
│   ├── spectator.sp          # Spectator behavior
│   ├── statistics.sp         # Stats and rank display
│   ├── rating/
│   │   ├── rating_core.sp    # Rating_ReportResult dispatcher, display/leaderboard/win-chance helpers
│   │   ├── engine_elo.sp # Default rating engine (original ELO math, unchanged)
│   │   ├── engine_glicko2.sp # Opt-in Glicko-2 math (mgemod_rating_engine "glicko2")
│   │   └── glicko_period.sp # Wall-clock period close (only if mgemod_glicko_period_close 1), lock, leftover, HUD estimates
│   ├── gamemodes/
│   │   ├── bball.sp          # Basketball mode
│   │   ├── koth.sp           # King of the Hill mode
│   │   ├── 2v2.sp            # 2v2 team mode
│   │   ├── ammomod.sp        # Ammomod mode
│   │   └── endif.sp          # Endif mode
│   └── api/
│       ├── forwards.sp       # Plugin forwards for extension hooks
│       └── natives.sp        # CreateNative API for other plugins
├── include/
│   ├── mge.inc               # Public API: constants, enums, forwards, natives
│   ├── morecolors.inc        # Chat color formatting library
│   └── convar_class.inc      # ConVar helper methodmap
```

### Key Include: `mge.inc`

The public API header. Contains:
- Gamemode bitmask constants (`MGE_GAMEMODE_MGE`, `MGE_GAMEMODE_BBALL`, etc.)
- Slot and team constants
- `MGEPlayerStats` and `MGEArenaInfo` enum structs
- Arena status enum (`AS_IDLE` through `AS_WAITING_READY`)
- All forward and native declarations

## Core Concepts

| Concept | Description |
|---------|-------------|
| **Arena** | A labeled duel area on a map. Defined per-map in `configs/mge/<mapname>.cfg`. Max 63 arenas, 128 spawns each. |
| **Gamemode** | Per-arena mode: `mge`, `bball`, `koth`, `ammomod`, `midair`, `endif`, `ultiduo`, `turris`. Stored as bitmask flags. |
| **Slot** | Player position in an arena (1–4). Slots 1–2 for 1v1, slots 1–4 for 2v2. |
| **Queue** | Players join arenas via `!add` or menu. Losers rotate out when queue has waiting players. |
| **Arena Status** | State machine: `IDLE → PRECOUNTDOWN → COUNTDOWN → FIGHT → AFTERFIGHT → REPORTED`. Also `WAITING_READY` for 2v2. |
| **ELO** | Persistent rating stored in DB. Optional — plugin works without a database. |
| **Rating Engine** | Pluggable algorithm behind ELO: `elo` (default, live K-factor) or `glicko2` (opt-in). Glicko-2 seals `rating`/`rd`/`volatility` on a wall-clock period. HUD may show `~` from `rating_est`. See `mge/rating/` and [docs/glicko2-24h-period-walkthrough.md](docs/glicko2-24h-period-walkthrough.md). |
| **Frag Limit** | Score target to win a match. Configurable per-arena. |

## Data Model

State is managed through **parallel global arrays** indexed by arena ID and client index (defined in `globals.sp`). There are no heavy OOP abstractions — this is idiomatic SourcePawn.

Key arrays include per-arena score, spawn points, gamemode flags, KOTH entities, and per-player arena membership, slot assignment, and stats.

## Map Configuration Format

Arena definitions live in `addons/sourcemod/configs/mge/<mapname>.cfg` using **KeyValues** format:

```
"SpawnConfigs"
{
    "Arena Display Name"
    {
        "gamemode"              "mge"
        "team_size"             "2v2 1v1"
        "frag_limit"            "20"
        "countdown_seconds"     "3"
        "allowed_classes"       "scout soldier demoman"
        "hp_multiplier"         "1.25"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "min_spawn_distance"    "350"
        "spawns"
        {
            "red" { ... }
            "blu" { ... }
        }
    }
}
```

Additional per-arena keys: `min_elo`, `max_elo`, `airshot_min_height`, `knockback_boost`, `visible_hoops`, `early_leave_threshold`, `allow_koth_switch`, `koth_team_spawns`, `respawn_delay`, `allow_class_change`, `koth_round_time`.

## Coding Conventions

- **`#pragma semicolon 1`** and **`#pragma newdecls required`** — enforced globally.
- **Prefixes**: globals use `g_` prefix (`g_bLate`, `g_iDefaultFragLimit`, `g_sMapName`). Hungarian-ish notation: `b` = bool, `i` = int, `s` = string/char array, `h` = Handle.
- **Constants**: `SCREAMING_SNAKE_CASE` (`MAXARENAS`, `SLOT_ONE`, `MODEL_POINT`).
- **Functions**: `PascalCase` for public/stock functions, matching SourceMod conventions.
- **Enums**: `PascalCase` with descriptive prefixes (`AS_IDLE`, `DB_SQLITE`).
- **ConVars**: created via the `Convar` methodmap from `convar_class.inc`.
- **Chat colors**: use `<morecolors>` library (`CPrintToChat`, etc.).
- **Translations**: all user-facing strings go through `mgemod.phrases.txt` using `%t` formatting.
- **MAXPLAYERS hack**: redefined to 101 at the top of `mge.sp` for unrestricted player support.

## Database

Supports three backends (auto-detected from SourceMod's `databases.cfg`):
- **SQLite** (default, no setup needed)
- **MySQL**
- **PostgreSQL** (≤9.6 due to SourceMod driver limitations)

Schema is managed through `migrations.sp` — migrations run automatically on plugin load. The plugin functions without a database (stats/ELO disabled).

`mgemod_stats.rating` is shared by both engines. Under **Elo** it updates every duel. Under **Glicko-2** it is the **sealed** rating and only moves when a wall-clock period closes (`glicko_period.sp`), and only on the instance with `mgemod_glicko_period_close 1` (the localhost DB host). HUD preview columns `rating_est` / `rd_est` / `period_dirty` are not read by `!top`, platform, or the website. `rd` and `volatility` (nullable, migration `007_add_glicko_columns`) are only meaningful when `mgemod_rating_engine` is `glicko2`. **`rd IS NULL` means Elo. `rd IS NOT NULL` means Glicko-2.** Period schema is migration `009_glicko_period_schema`. Full decisions and test notes: [docs/glicko2-24h-period-walkthrough.md](docs/glicko2-24h-period-walkthrough.md).

## Build & Release

- **Local**: run `spcomp` with the include path pointing at `addons/sourcemod/scripting/include/`.
- **CI**: GitHub Actions (`.github/workflows/build.yml`) triggers on `v*` tags. Uses `rumblefrog/setup-sp` with SourcePawn 1.12.x, compiles, downloads large map BSPs, zips into a release artifact.
- **Output**: `addons/sourcemod/plugins/mge.smx` (compiled binary — not committed to repo).

## Important Constraints

- **TF2 only**: plugin fails to load on non-TF2 engines (`Engine_TF2` check in `AskPluginLoad2`).
- **SourcePawn limitations**: no classes/inheritance, limited string handling, fixed-size arrays. Use `enum struct` for structured data.
- **Include order matters**: modules in `mge.sp` are included in dependency order. Don't rearrange without checking cross-references.
- **No separate compilation**: all `.sp` files under `mge/` are `#include`d into `mge.sp`. They share the global scope.
- **Array bounds**: `MAXARENAS` (63) and `MAXSPAWNS` (128) are hard limits. Always bounds-check arena/spawn indices.
