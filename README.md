# MGEMod
> A 1v1 and 2v2 training mod for Team Fortress 2

This is a fork of sappho's repository, with the following improvements:

## New Commands

* Added `!elo` command to toggle client score display (like a local-only no stats)
* Modified `!add` command to support a player name as argument to join the arena that player is in (`!add @ampere`)
* Enhanced `!rank` command to display comprehensive player statistics in a panel interface

## New ConVars

* `mgemod_clear_projectiles` (0/1) - allow server owners to enable/disable projectile deletion upon the start of a new round
* `mgemod_rating_engine` (`elo`/`glicko2`) - selects the rating engine used to score every duel. Defaults to `elo`, which is the exact same math as before this convar existed. See [Rating Engines](#rating-engines) below.
* `mgemod_glicko_tau` (float) - Glicko-2 system constant controlling how fast volatility can change. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_period_hours` (int, default 24, range 1-168) - wall-clock length of one Glicko-2 rating period. 12 seals twice a day; 48 seals every other day. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_period_hour` / `mgemod_glicko_period_minute` / `mgemod_glicko_period_utc_offset` - phase of the period boundary in local time. mge.tf uses `08:20` ART (`utc_offset -3`). Do not set the boundary to `:00` if the box restarts on the hour. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_period_close` (0/1, default 0) - this instance runs the 24h period close. Set `1` only on the srcds that shares the box with MariaDB (localhost). Other game servers that talk to the same DB over the network leave this at `0`. Third-party single-server installs set it to `1`. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_period_days` (float) - inactivity knob: how many missed wall-clock periods of RD inflation to apply when a player does not play. Default `1.0` means one Glicko period of RD growth per missed window. This is not the seal interval (that is `mgemod_glicko_period_hours`). Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_provisional_rd` (float) - RD threshold above which a player's rating is considered provisional. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_ranked_rd` (float) - RD threshold a player must be below to appear on `!top` and external leaderboards. Only used when `mgemod_rating_engine` is `glicko2`.
* `mgemod_glicko_ranked_min_games` (int) - minimum games (wins+losses) a player needs to appear on `!top` and external leaderboards. Only used when `mgemod_rating_engine` is `glicko2`.

## Rating Engines

MGEMod supports two pluggable rating engines, selected server-wide via `mgemod_rating_engine`. Only one engine is active at a time; there is no dual leaderboard.

* **Elo (default)**: the original K-factor Elo formula this plugin has always used. Selecting this engine (or leaving the convar untouched) is a zero-behavior-change no-op.
* **Glicko-2 (opt-in)**: an extension of Elo that tracks each player's Rating Deviation (RD, a confidence measure) and Volatility (how erratic their results are) alongside their rating. This lets the system react faster to smurfs and improving players. Inactive players' RD grows, which marks their rating as provisional (`?`) until they play again. See [glicko.net](http://www.glicko.net/glicko/glicko2.pdf) for the published algorithm this implementation follows.

Under Glicko-2, a **rating period is a wall-clock window** (`mgemod_glicko_period_hours`, default 24h), not one duel. Each 1v1 appends a row to `mgemod_duels` with a freeze of both players' **sealed** rating/RD/volatility. Wins/losses update immediately. Sealed `mgemod_stats.rating` / `rd` / `volatility` only change when a period closes. HUD estimate columns (`rating_est` / `rd_est` / `period_dirty`) are written after each 1v1 so the arena HUD can show a preview as `~2450`. `!top`, `!rank`, the platform poller, and the website read the sealed `rating` column. After close, estimate is copied from the seal and the tilde drops. `?` still means provisional **sealed** RD.

Period close runs **inside the plugin** (30s timer plus a lazy close on boot), but **only** on instances with `mgemod_glicko_period_close 1`. Default is `0`: a fleet of game servers sharing one MariaDB must elect the closer (the box that hosts the DB, connecting over localhost). The advisory lock remains as a second line of defense if more than one instance on that box has the cvar on. Empty closer boxes must keep ticking: set `sv_hibernate_when_empty 0`. Because mge.tf boxes already restart every hour, the boot lazy-close is the real safety net. Do not align the close phase with the restart cron (`:00`). Cross-server election uses a **per-SQL-driver advisory lock** on the same stats Database handle (`GET_LOCK` on MySQL/MariaDB, `pg_try_advisory_lock` on Postgres, `BEGIN IMMEDIATE` on SQLite). This is not `SQL_LockDatabase`, which is only an in-process threader mutex and cannot coordinate other srcds instances. Match-end INSERTs do not take that lock. Classelo uses a different lock name so it does not queue behind overall.

Several 1v1s in the same window become one Glicko period (one `phiStar`). One game per window is still one period each. That is expected, not a missed batch.

2v2 duels do **not** write rating, RD, or volatility under either engine. Wins/losses still increment and `mgemod_duels_2v2` is still inserted for audit. `mgemod_2v2_elo` only gates whether 2v2 HUD lines show rating digits.

`!top` and the external leaderboards (platform API, website) apply a stricter "ranked" bar on top of the provisional flag: a player only shows up there once their **sealed** RD drops below `mgemod_glicko_ranked_rd` (default 100) and they've played at least `mgemod_glicko_ranked_min_games` (default 10) games. This keeps someone's first lucky win from parking them at #1. `!rank` is exempt from this gate: it always shows your own sealed rank/rating (with the `?` marker if provisional), plus a "Leaderboard: Ranked" / "Leaderboard: Not ranked (...)" line explaining whether and why you're missing from the public tables.

Both engines share the same `rating` column and the same leaderboard/`!rank`/`min_elo`/`max_elo` gating; Glicko-2 additionally persists `rd` and `volatility` in two nullable columns on `mgemod_stats`. Nullability of `rd` is a strict, unambiguous engine signal: **`rd IS NULL` always means Elo is active, `rd IS NOT NULL` always means Glicko-2 is active** - never "Glicko-2 player who just hasn't played a duel yet". New players get `rd = 350`, `volatility = 0.06` written immediately when their row is created (not lazily on first duel), migration `008_seed_glicko_rd_defaults` backfills any pre-existing rows once, and switching `mgemod_rating_engine` at runtime re-syncs every row both ways (populates defaults when turning Glicko-2 on, clears both columns when turning it off). External tools (the platform sync, the website) rely on this invariant to tell Elo regions and not-yet-established Glicko-2 players apart.

2v2 duels do not move `rating` under either engine. Wins/losses and the 2v2 duel log still persist. `mgemod_2v2_elo` only controls whether rating digits appear on 2v2 HUD lines.

## Database & Backend

* Added a database migration mechanism to leave room for future features and improvements that require modifying the schema
* Fixed some database connection issues
* Added PostgreSQL support (only <=9.6 as per SourceMod's limitations)
* MySQL connections call `SetCharset("utf8mb4")` after connect so player names from `GetClientName` are stored correctly (SourceMod 1.10+; pairs with the `005_utf8mb4_charset` table migration)
* Added some measures to prevent ELOs from corrupting randomly due to database connection errors
* Added an API layer of natives and forwards
* Added ELO verification system to prevent players with failed Steam authentication from affecting ratings

## Duel & Statistics Tracking

* Added class tracking in duels
* Added start time tracking in duels
* Added previous and new score tracking in duels
* Added elo tracking in duels, displaying previous elo and new elo of each player in every match record

## Arena & Gameplay

* Split the `mgemod_spawns.cfg` file into map-specific files for better performance and UX while editing arenas
* Added the possibility of blocking class change once the duel has started and score is still 0-0, via a new arena `classchange` property in the map config file
* Blocked eureka effect teleport usage
* Blocked the repeating resupply sound due to some maps not blocking them in certain arenas
* Fixed a small bug in the random spawn logic
* Attempted to fix situations of death momentum carryover on respawn, which results in respawning with non-zero velocity

## User Interface & Experience

* Fixed arena player count display in the !add menu not working properly
* Fixed HUD not reflecting changes on time or not displaying players properly sometimes
* Improved the interface and usage experience of the !top5 menu
* Fixed some sounds not working due to the plugin using their .wav version instead of .mp3
* Forced menu close on players that had the !add menu open but decided to join an arena via chat
* Fixed some commands not having their return type properly, making users users receive "Unknown command"
* Added missing translations for all hardcoded english strings, and added some languages

## 2v2 System

* Implemented a new menu upon selecting a 2v2 arena to join a specific team, or to switch that arena to 1v1
* Implemented a ready system
  * Plugin prompts players for their ready status once it detects 2 players per team in the arena
  * Players can either confirm ready via menu or `!r`/`!ready` commands in chat
  * Players get notified of everyone in the arena's ready status via a center hint text
* Players can switch teams either via the !add menu selecting their current arena, or switching teams manually
* Added `mgemod_2v2_skip_countdown` (0/1) ConVar to allow server owners to enable/disable countdown between 2v2 rounds (author: [tommy-mor](https://github.com/sapphonie/MGEMod/pull/24))
* Fixed names sometimes getting cut off in the HUD text
* Improved displaying player names in the HUD
* Teammates no longer spawn in the same spot
* Added `mgemod_2v2_elo` (0/1) ConVar to allow server owners to enable/disable rating digits on 2v2 HUD lines. 2v2 never writes rating/RD/volatility.

## Developer Experience

* Reduced log verbosity in console when loading the plugin
* Modernized some parts of the source code with methodmap usage
* Fixed some bugs with `!botme` usage
* Completely modularized the code in separate script files to reduce the +7000 lines main file

The plugin is ready to be a drop-in replacement for the standard MGE version. Database modifications will be performed automatically and safely.

## Map Config File Format

MGEMod loads arena definitions from per-map KeyValues config files. This section documents the full format for mapmakers who want to ship MGE arenas with their map.

### File Location and Naming

Config files live at:

```
addons/sourcemod/configs/mge/<mapname>.cfg
```

The filename must exactly match the map name as reported by the game engine (e.g. `mge_training_v8_beta4b.cfg` for `mge_training_v8_beta4b`). Workshop maps are automatically converted from their workshop ID to their display name.

### File Structure

The root key must be `SpawnConfigs`. Each child key is an arena, identified by its **display name** (shown in the `!add` menu and HUD). Arena names must be unique within the file.

```
SpawnConfigs
{
    "Arena Display Name"
    {
        // ... arena properties ...

        "spawns"
        {
            // ... spawn points ...
        }
    }

    "Another Arena"
    {
        // ...
    }
}
```

**Hard limits:** maximum **63 arenas** per file, maximum **15 spawns** per arena.

---

### Arena Properties

#### Core Properties

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `gamemode` | string | `"mge"` | Game mode for this arena. See [Gamemodes](#gamemodes) for valid values. |
| `team_size` | string | `"1v1"` | Team format. `"1v1"`, `"2v2"`, or two values separated by a space to allow switching (e.g. `"1v1 2v2"` or `"2v2 1v1"`). The first value sets the starting mode; the second enables `!1v1`/`!2v2` commands for in-game switching. |
| `frag_limit` | int | server cvar | Frags (or caps for KOTH) required to win the match. |
| `countdown_seconds` | int | server cvar | Seconds in the pre-match countdown before "FIGHT". Set to `0` to skip the countdown entirely. |
| `allowed_classes` | string | server cvar | Space-separated list of TF2 class names permitted in this arena: `scout soldier demoman sniper medic heavy engineer spy pyro`. If omitted, falls back to the server's default allowed classes. |

#### HP and Ammo

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `hp_multiplier` | float | `1.5` | Multiplier applied to each player's base max HP on spawn. `1.25` gives a Soldier 150 HP instead of 200; `1.0` gives stock HP. |
| `infinite_ammo` | 0/1 | `1` | Give unlimited ammo. Disable for standard MGE arenas where ammo management matters. |
| `show_hp` | 0/1 | `1` | Show players' current HP in the arena HUD. |

#### Spawning

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `min_spawn_distance` | float | `100.0` | Minimum distance (in Hammer units) required between two randomly selected spawn points. Prevents players from spawning on top of each other. Increase this for larger arenas. |
| `respawn_delay` | float | `0.1` | Seconds before a dead player respawns. Use higher values (e.g. `2.0` for BBall, `5.0`–`10.0` for KOTH/Ultiduo) to create respawn pressure. |

#### ELO Gating

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `min_elo` | int | `-1` (disabled) | Minimum ELO rating a player must have to join this arena. `-1` disables the check. |
| `max_elo` | int | `-1` (disabled) | Maximum ELO rating allowed in this arena. `-1` disables the check. |

#### Match Rules

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `early_leave_threshold` | int | `0` | If a player leaves mid-match and their opponent has more than this many points, the opponent is awarded the win: rating updates and a `mgemod_duels` row is written. At or below the threshold (e.g. 5-5 with threshold 5) there is no rating change, no duel log, and no match-end forward. `0` disables early-leave wins. |
| `allow_class_change` | 0/1 | `1` | Whether players can change class during a duel. When set to `0`, class switching is locked after the first point is scored. |
| `airshot_min_height` | int | `250` | Minimum height above ground (in Hammer units) for a kill to be counted as an airshot in stats. |
| `knockback_boost` | 0/1 | `0` | Enable engine knockback boost vectors. Experimental. |

#### KOTH-Specific

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `koth_round_time` | int | `180` | Duration in seconds of each KOTH round timer. |
| `allow_koth_switch` | 0/1 | `0` | Allow players in this arena to switch it between KOTH and MGE modes using `!koth`/`!mge` commands. |
| `koth_team_spawns` | 0/1 | `0` | Use team-split spawn sections instead of flat spawn list when this arena is in KOTH mode. |

#### BBall-Specific

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `visible_hoops` | 0/1 | `0` | Make the basketball hoops visible as world props. |

---

### Spawn Coordinate Format

Each spawn point is a quoted string of space-separated numbers. Two formats are accepted:

**6-value format** — `"X Y Z pitch yaw roll"` (full rotation)
```
"1"    "1234.5 -678.9 -100.0 0.0 90.0 0.0"
```

**4-value format** — `"X Y Z yaw"` (pitch and roll default to 0)
```
"1"    "1234 -678 -100 90"
```

All coordinates are in **Hammer units**. Angles follow TF2 conventions: pitch is the vertical look angle (negative = looking up), yaw is the horizontal facing direction (0 = +X axis, 90 = +Y, −90/270 = −Y, 180/−180 = −X), and roll is almost always `0`.

---

### Spawn Section Formats

#### Flat Format

All spawns in a single numbered list. The plugin splits them evenly: the first half goes to RED, the second half to BLU. Players are assigned spawn points randomly from their team's pool. Use this for simple 1v1 arenas.

```
"spawns"
{
    "1"    "X Y Z pitch yaw roll"
    "2"    "X Y Z pitch yaw roll"
    "3"    "X Y Z pitch yaw roll"
    "4"    "X Y Z pitch yaw roll"
}
```

Spawns `1`–`2` are assigned to RED, spawns `3`–`4` to BLU.

#### Team-Split Format

RED and BLU spawn points defined in separate subsections. Required when the two teams have different spawn areas. Works for both 1v1 and 2v2 arenas. Use up to 4 spawns per team for 2v2 arenas so all four players get distinct positions.

```
"spawns"
{
    "red"
    {
        "1"    "X Y Z pitch yaw roll"
        "2"    "X Y Z pitch yaw roll"
    }
    "blu"
    {
        "1"    "X Y Z pitch yaw roll"
        "2"    "X Y Z pitch yaw roll"
    }
}
```

#### Class-Specific Format

Spawns further subdivided by class within each team. **Required for `ultiduo` arenas**, which must have separate spawn positions for soldiers and medics on both teams. Class names must be lowercase TF2 class identifiers.

```
"spawns"
{
    "red"
    {
        "soldier"
        {
            "1"    "X Y Z pitch yaw roll"
            "2"    "X Y Z pitch yaw roll"
        }
        "medic"
        {
            "1"    "X Y Z pitch yaw roll"
            "2"    "X Y Z pitch yaw roll"
        }
    }
    "blu"
    {
        "soldier"
        {
            "1"    "X Y Z pitch yaw roll"
            "2"    "X Y Z pitch yaw roll"
        }
        "medic"
        {
            "1"    "X Y Z pitch yaw roll"
            "2"    "X Y Z pitch yaw roll"
        }
    }
}
```

---

### Entities Section

The `entities` block defines world positions for dynamic objects created by certain gamemodes. Coordinates use the format `"X Y Z yaw"` (only the XYZ position is used; yaw is parsed but ignored for most entity types).

```
"entities"
{
    "key"    "X Y Z yaw"
}
```

| Key | Required for | Description |
|-----|-------------|-------------|
| `hoop_red` | `bball` | Position of the RED team's basketball hoop. |
| `hoop_blu` | `bball` | Position of the BLU team's basketball hoop. |
| `intel_start` | `bball` | Starting position of the ball (intelligence item). |
| `intel_red` | `bball` | Position of the RED intel return zone. |
| `intel_blu` | `bball` | Position of the BLU intel return zone. |
| `capture_point` | `koth`, `ultiduo` | Position of the KOTH capture point. |

BBall arenas will fail validation and be skipped if `hoop_red`, `hoop_blu`, or `intel_start` are missing. KOTH and Ultiduo arenas will be skipped if `capture_point` is missing.

---

### Gamemodes

| Value | Description |
|-------|-------------|
| `mge` | Standard MGE. First to `frag_limit` kills wins. |
| `bball` | Basketball. Score by rocketing the ball into the opponent's hoop. Requires a full `entities` block. |
| `koth` | King of the Hill. Hold the capture point to drain the opponent's timer. Requires `capture_point` in `entities`. |
| `ammomod` | Ammomod. Disables splash damage; players fire faster and receive high HP. |
| `midair` | Midair only. Only airborne kills count toward the score. |
| `endif` | Endif. Players have infinite ammo and no splash damage; kill to score. |
| `ultiduo` | 2v2 KOTH with Soldier + Medic per team. Requires class-specific spawns (both `soldier` and `medic` subsections under `red` and `blu`) and a `capture_point` entity. |
| `turris` | Turris. Players continuously regenerate HP while alive. |

---

### Complete Examples

#### Standard 1v1 MGE Arena (flat spawns)

```
SpawnConfigs
{
    "Badlands Middle"
    {
        "gamemode"              "mge"
        "team_size"             "1v1"
        "frag_limit"            "20"
        "countdown_seconds"     "3"
        "allowed_classes"       "soldier demoman scout sniper"
        "hp_multiplier"         "1.25"
        "early_leave_threshold" "3"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "min_spawn_distance"    "550"

        "spawns"
        {
            "1"    "-11686 -13377 -773 0"
            "2"    "-11248 -13521 -773 0"
            "3"    "-10279 -13526 -773 180"
            "4"    "-9849  -13380 -773 178"
        }
    }
}
```

#### 2v2-Switchable Arena (team-split spawns)

```
SpawnConfigs
{
    "Granary Middle"
    {
        "gamemode"              "mge"
        "team_size"             "1v1 2v2"
        "frag_limit"            "20"
        "allowed_classes"       "scout soldier demoman sniper"
        "hp_multiplier"         "1.25"
        "early_leave_threshold" "3"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "min_spawn_distance"    "700"

        "spawns"
        {
            "red"
            {
                "1"    "10035 -4285 -1425 0.0 -45.0 0.0"
                "2"    "10505 -4275 -1520 0.0 -90.0 0.0"
            }
            "blu"
            {
                "1"    "10955 -5705 -1425 0.0 135.0 0.0"
                "2"    "10495 -5700 -1520 0.0  90.0 0.0"
            }
        }
    }
}
```

#### BBall Arena (2v2, with entities)

```
SpawnConfigs
{
    "BBall Court 1"
    {
        "gamemode"              "bball"
        "team_size"             "2v2"
        "frag_limit"            "10"
        "countdown_seconds"     "1"
        "allowed_classes"       "soldier"
        "hp_multiplier"         "1"
        "early_leave_threshold" "1"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "respawn_delay"         "2.0"
        "visible_hoops"         "0"

        "spawns"
        {
            "red"
            {
                "1"    "100  -960 32 90"
                "2"    "200  -960 32 90"
            }
            "blu"
            {
                "1"    "100   960 32 270"
                "2"    "200   960 32 270"
            }
        }
        "entities"
        {
            "intel_start"    "150    0 142 0"
            "intel_red"      "150  512  96 0"
            "intel_blu"      "150 -512  96 0"
            "hoop_red"       "150 -796 135 0"
            "hoop_blu"       "150  796 135 0"
        }
    }
}
```

#### KOTH Arena (with capture point)

```
SpawnConfigs
{
    "KOTH Arena"
    {
        "gamemode"              "koth"
        "team_size"             "1v1"
        "frag_limit"            "2"
        "countdown_seconds"     "3"
        "allowed_classes"       "soldier demoman"
        "hp_multiplier"         "1"
        "early_leave_threshold" "1"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "min_spawn_distance"    "400"
        "koth_round_time"       "120"
        "respawn_delay"         "5.0"

        "spawns"
        {
            "red"
            {
                "1"    "500 300 -100 -45"
                "2"    "600 200 -100 -45"
            }
            "blu"
            {
                "1"    "500 -300 -100 135"
                "2"    "600 -200 -100 135"
            }
        }
        "entities"
        {
            "capture_point"    "550 0 50 0"
        }
    }
}
```

#### Ultiduo Arena (class-specific spawns)

```
SpawnConfigs
{
    "Ultiduo"
    {
        "gamemode"              "ultiduo"
        "team_size"             "1v1"
        "frag_limit"            "2"
        "countdown_seconds"     "1"
        "allowed_classes"       "soldier medic"
        "hp_multiplier"         "1"
        "early_leave_threshold" "1"
        "infinite_ammo"         "0"
        "show_hp"               "0"
        "respawn_delay"         "10.0"

        "spawns"
        {
            "red"
            {
                "soldier"
                {
                    "1"    "-2512  1040 0 -90"
                    "2"    "-2560  1040 0 -90"
                }
                "medic"
                {
                    "1"    "-2608  1040 0 -90"
                }
            }
            "blu"
            {
                "soldier"
                {
                    "1"    "-2512 -1040 0 90"
                    "2"    "-2560 -1040 0 90"
                }
                "medic"
                {
                    "1"    "-2608 -1040 0 90"
                }
            }
        }
        "entities"
        {
            "capture_point"    "-2567 -7 -228 0"
        }
    }
}
```

---

## Pending bug fixes and ideas

### Hot Reload Support

The plugin may have bugs when hot-reloaded (reloaded without server restart) due to incomplete cleanup of player states, arena data, and database connections. This can cause players to get stuck in arenas, lose their ratings, or experience other state inconsistencies. Hot reload support is halfway through, either complete or remove.

### Arena Property Editing

Currently requires manually editing map config files and reloading the plugin/map to change arena properties like spawn points, class restrictions, or game modes. This is time-consuming and error-prone for server administrators.

**Implementation ideas:**
- Add in-game arena property editor commands
- Create web-based configuration interface
- Implement real-time arena property updates
- Add arena property validation and error checking

### Mapmaker Configuration System

Mapmakers currently need to manually create and edit complex config files for their MGE maps, which requires understanding the plugin's configuration syntax and can be error-prone.

**Implementation ideas:**
- Create interactive map configuration tool/plugin
- Build visual arena placement and property editor
- Implement config file generation from in-game setup
- Add configuration templates and wizards for common map types

### 2v2 ELO Display in HUD

The ELO display logic in 2v2 mode is confusing since individual ELOs get merged/combined in 2v2 matches. The current implementation may not be relevant or useful for players in 2v2 scenarios.

**Decision needed:**
- Remove ELO display from 2v2 HUD entirely
- Implement team-based ELO calculation and display
- Show individual ELOs but with clear indication they're not used for 2v2 matchmaking
- Redesign ELO system to be more intuitive for 2v2 gameplay

### Make all timers configurable

Make game start, round start, game end, round end and any other timer configurable.