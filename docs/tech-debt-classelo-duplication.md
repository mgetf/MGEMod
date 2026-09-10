# Tech debt: MGEMod ↔ classelo code duplication

Status: **documented, not started.** This is a target design (Plan B below), not a task in flight. Do not start it opportunistically inside an unrelated change — it deserves its own PR(s) with its own test pass on a local srcds against SQLite/MySQL/PostgreSQL.

## Why this file exists

While adding [`mgemod_glicko_close_log`](./glicko2-24h-period-walkthrough.md) (migration `010_add_glicko_close_log`) to MGEMod, the obvious next step was "now copy the same table + insert call into `mge-classelo`, like every other Glicko-2 feature has been ported by hand since 007". That reflex is exactly the problem: classelo and MGEMod have drifted into carrying **two independent, hand-synced copies** of logic that should be one.

## What is duplicated, with evidence

### 1. Pure Glicko-2 math — should be byte-identical, is currently copy-pasted

| MGEMod (`addons/sourcemod/scripting/mge/rating/engine_glicko2.sp`) | classelo (`scripting/mge_classelo.sp`) |
|---|---|
| `Glicko2_G` | `ClassGlicko2_G` (line 810) |
| `Glicko2_E` | `ClassGlicko2_E` (line 816) |
| `Glicko2_F` | `ClassGlicko2_F` (line 823) |
| `Glicko2_InflateRdOnePeriod` | `ClassGlicko2_InflateRdOnePeriod` (line 834) |
| `Glicko2_ComputePeriodUpdate` | `ClassGlicko2_ComputePeriodUpdate` (line 844) |
| `Glicko2_ComputeUpdate` | (inlined equivalent) |

Compared line by line: these are the **same algorithm, same variable names, same Illinois-method root finder**, with only a `Class`/`CLASS_` prefix swapped in. Roughly 170 lines, no game-specific logic in any of them — they take rating/rd/volatility/opponent arrays in, return new values out, touch no globals, make no DB calls. Zero reason for these to be two files.

### 2. The 24h period-close state machine — same algorithm, different table names

| MGEMod (`addons/sourcemod/scripting/mge/rating/glicko_period.sp`, 772 lines) | classelo (`ClassPeriod_*`, ~830 lines, `scripting/mge_classelo.sp` lines 1241-2071) |
|---|---|
| `GlickoPeriod_TryLock` / `_OnLockResult` | `ClassPeriod_TryLock` / `_OnLockResult` |
| `GlickoPeriod_OnMeta` / `_OnBootstrapped` | `ClassPeriod_OnMeta` / `_OnBootstrapped` |
| `GlickoPeriod_FetchPeriodDuels` / `_OnPeriodDuels` | `ClassPeriod_FetchPeriodDuels` / `_OnPeriodDuels` |
| `GlickoPeriod_OnStats` / `_FillFromGames` | `ClassPeriod_OnStats` / `_ComputeFromGames` |
| `GlickoPeriod_QueueUpdates` / `_FlushUpdateChunk` | `ClassPeriod_QueueUpdates` / `_FlushUpdateChunk` |
| `GlickoPeriod_OnSealed` / `_FetchLeftovers` | `ClassPeriod_OnSealed` / `_FetchLeftovers` |
| `GlickoPeriod_NotifyConnectedClients` / `_Finish` | `ClassPeriod_NotifyConnectedClients` / `_Finish` |

Function-for-function, the flow is identical: advisory lock → read `last_sealed_period_id` → pull unsealed duels for the target period → recompute period-batched Glicko-2 per player → chunked transactional `UPDATE` → mark duels sealed → leftover recompute passes (max 3) → release lock. The only real differences are: table names (`mgemod_stats`/`mgemod_duels`/`mgemod_period_state` vs `mge_classelo_*`), an extra `class` column in every key/query, and the period length convar (`mgemod_glicko_period_hours` vs `mge_classelo_glicko_period_hours`, default 7-day unused-class window).

### 3. Schema/migrations — different systems entirely

MGEMod has a real migration framework (`migrations.sp`: versioned, idempotent, tracked in `mgemod_migrations`). classelo re-invented a lighter one-off version (`ClassPeriod_EnsureSchema` / `ClassPeriod_RunSchemaStep`) instead of sharing the framework. Lower priority than #1/#2 — schema changes are rare — but worth folding in if #1/#2 ever get tackled.

## What is *not* duplication (keep as-is)

Documented as an intentional decision in [`glicko2-24h-period-walkthrough.md` §3.7](./glicko2-24h-period-walkthrough.md#37-classelo-is-independent-same-clock):

- classelo has its **own** table, own close, own estimate columns, own lock name (`mge_classelo_period_close`).
- classelo's unused-class RD inflation window defaults to 7 days, not MGE's 1-day period — genuinely different product behavior, not a bug.
- Both plugins call `GetClientAuthId` independently; no shared Steam ID native (a prior `sm_mge_setsteamid` hack was removed on purpose — see §8 "what must not be reintroduced").

**Do not merge the plugins or couple their runtime versions.** The goal below is to share source, not to make classelo depend on MGEMod being loaded, a specific MGEMod version, or a shared native/forward at runtime.

## Concrete cost already observed

This is not theoretical. In the same session that added `mgemod_glicko_close_log` to MGEMod:

- classelo has **no** close-delta audit log at all today — nobody remembered to port `MGE_OnPlayerRatingChange`-style audit logging over when 009/010 shipped on the MGEMod side.
- The natural next step was "go copy-paste the new table + insert call into classelo", which is precisely how the two ~800-line state machines got this far out of sync in the first place.

## Proposed remediation (Plan B — chosen target, not yet started)

1. **Extract the pure math (§1 above) into a shared `.inc`**, e.g. `glicko2_math.inc`, containing `Glicko2_G/E/F/InflateRdOnePeriod/ComputePeriodUpdate/ComputeUpdate` with their real (non-`Class`-prefixed) names and the constants they need (`GLICKO2_SCALE`, `GLICKO2_PI`, `GLICKO2_E`, `GLICKO2_MAX_RD`, `GLICKO2_CONVERGENCE_EPSILON`). Both `mge.sp` and `mge_classelo.sp` `#include` it. This is safe: it's a textual include with no runtime coupling — each plugin still compiles independently into its own `.smx`, so classelo is never version-locked to a specific MGEMod build. `tau` stays a per-plugin convar passed as a parameter, not baked into the shared file.

2. **Templatize the period-close orchestration (§2 above)** into a second shared `.inc` (e.g. `glicko_period_engine.inc`). This is the more invasive step: today table/column names are hardcoded literals inside SQL strings built with `g_DB.Format`. To share the state machine, every query-building function needs to take the stats table name, duels table name, period-state table name, and an optional extra key column (`class`) as parameters (or the caller supplies small query-builder callbacks). The lock name, period-length convar, and leftover-pass limit already are per-caller parameters/convars and need no change.

3. **Decide on a distribution mechanism** for the shared `.inc` files across the two repos before starting #2. SourceMod has no package manager; the two realistic options are (a) vendor a copy of the `.inc` into each repo with a CI check that diffs it against a canonical source (e.g. MGEMod) and fails the build on drift, or (b) a small release script that copies the file from MGEMod into `mge-classelo` as part of cutting a release. Pick whichever fits the existing `.github/workflows/build.yml` release flow with the least new infra.

4. **Fold schema (§3) into the shared migration framework last**, once #1/#2 are stable — lowest priority, and reshaping classelo's ad-hoc `ClassPeriod_EnsureSchema` into `migrations.sp`-style versioned steps touches its DB bootstrap path, which is riskier to change than pure functions.

## Non-goals

- Do not merge MGEMod and classelo into one plugin.
- Do not introduce a runtime dependency (native/forward call) between the two plugins for rating math — the whole point is shared *source*, not shared *runtime state*.
- Do not touch classelo's independent clock, table names, or 7-day window semantics.
- Do not let this block routine feature work indefinitely — if a new Glicko-2 feature needs to ship before #1 lands, hand-porting it (as done for `mgemod_glicko_close_log`, tracked separately) is an acceptable stopgap, but should be noted here if it happens again so this list doesn't go stale.

## Related docs

- [`glicko2-24h-period-walkthrough.md`](./glicko2-24h-period-walkthrough.md) — canonical design doc for the 24h period system this debt applies to.
- `mge-classelo/README.md` "Agent notes" section links back here.
