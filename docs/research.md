# Simulation and implementation evidence

Engine: WoWSims Forever `00fecd9cff1be57483e21c061ed50d69748ae056`, game data 1.60.1.70959 plus 2026-11-20 hotfixes, downloaded by the earlier equipment investigation from https://wuxianwow.com/sim/hunter-dps. WASM SHA256: `d5cd245aa6f0dedfcd516f46fc481bc959e1acf54d507098bbd4e6fedf5635f1`. Tests performed 2026-11-22. No live-client performance measurements.

One fixed sample equipment set (Bloodseeker +7 damage scope and Devilsaur two-piece), Troll, Jagged Arrows, 12% quiver, target level63/armor3731, player fixed60 because the engine cannot simulate59. Full raid preset includes idealized buffs such as Judgement of Wisdom; not a claim about any actual party. BM uses a cat at full uptime, MM and weaving SV use Lone Wolf/no pet. Full consumes exclude engineering explosives. Fixed duration, no deaths/target switches; SV movement is simulated. None of these DPS figures validates the shipped Lua's performance.

## Marksmanship

5/41/5, ranged only: 1628 strategy/scenario evaluations at100 iterations, then48 finalist evaluations at2000 with independent random seed. Broad ordering/skill/threshold exploration, not exhaustive APL search. Candidate openers and burst timings also differ, so improvements cannot be attributed solely to a threshold.

| Scenario | Preset DPS | Best tested candidate DPS |
|---|---:|---:|
| Unbuffed 180s |220.2|256.4|
| Raid, no consumes 180s |515.2|542.5|
| Raid + mana consumes 180s |648.7|649.4 (effectively tied)|
| Raid + full consumes 180s |778.3|783.1|
| Raid, no consumes 300s |473.3|520.9|

Conserve candidates dropped Aimed filler, maintained Sting and gated Arcane/Sniper. Full-consume candidates favored Sting then Arcane/Aimed/Sniper. Exact mana thresholds may be unavailable in game and are not guaranteed there. Estimated encounter-duration thresholds were NOT shipped.

## Beast Mastery

31/20/0. Twelve initial configurations per each of five scenarios at100 iterations; baseline and two finalists each1000, plus1000 each for3/6 targets. Independent final seed65897123. Tested Aimed on/off, Arcane in the Hawk cycle on/off, and0/15/30% resource gates. Identical gear/pet for all comparisons.

| Scenario | Baseline | Best tested |
|---|---:|---:|
| Unbuffed180s |269.3|297.3 (no Aimed,30% gate)|
| Raid180s |578.3|578.3|
| Full consumes180s |751.1|751.1|
| Short raid30s |787.3|787.3|
| Long raid300s |546.5|566.6 (no Aimed)|

The package keeps the confirmed Hawk/Hawk/Arcane sequence and offers an explicit conserve mode without Aimed. Actual hawk survival, pet travel and player reaction are not inferred from these averages.

## Survival weaving

0/20/31. Eighteen initial configurations per each of five scenarios at100 iterations: upstream Max/Normal/Pure weaving,12/13.19/16 simulation-unit distance,0/15% resource gates. Baseline, two finalists and300ms reaction sensitivity each1000, plus3/6-target cases1000. Simulator reach distances are not identical to displayed game yards.

| Scenario | Aggressive reference | Best tested |
|---|---:|---:|
| Unbuffed180s |187.4|226.6 (Normal +15% gate)|
| Raid180s |611.1|611.1 (aggressive)|
| Full consumes180s |739.5|820.8 (Normal)|
| Short raid30s |691.2|780.1 (Normal)|
| Long raid300s |575.4|575.4 (aggressive)|

Aggressive raid180 fell from611.1 to593.1 at300ms reaction; Normal full-consume fell from820.8 to814.4. Normal is the package default for robustness in solo/short/full-consume cases, not a claim it wins raid-no-consume. `/hcf weave aggressive` is an independent SV-only preference (persisted, default normal), separate from resource modes.

3/6-target total DPS checks: BM850.3/1202.1, SV1044.1/1245.4, MM1005.9/1548.6. These test AoE variants, not a proof of globally optimal target-count breakpoints. Never compare a single-target-only baseline to call this an optimization gain.

## Translation to addon

Only known-rank/usable/in-range skills enter the decision. The code does not implement exact simulator movement or future mana/TTD. Hand-operated resource mode and target-count controls replace unavailable state. Unknown auras do not count as absent; carefully associated cast timers are explicitly estimates. Numeric resource reserve uses at most a short2-second forecast when available. Traps are opt-in. Casting/channeling suppresses new instructions.

Multi-Shot is rankless in the pinned Forever source: `MultiShot: spelldata.Ranked(2643)`. Classic-only rank IDs are not appended without evidence. The current fixed rank tables do not auto-discover future ranks. Two confirmed casts followed by readable aura absence trigger a20-second per-target backoff; this is not immunity detection. Unknown Raptor queue state is not treated as unqueued.

Cooldown state: live NeverSecret isActive/isEnabled fields, event-context isOnGCD cache, readable numeric override and immediate successful-cast family invalidation. Secret/unknown usability fails closed. Secret values are never extracted via hidden widgets. Native duration objects are passed only to an owned cooldown for rendering.

Offline Lua5.1 tests and artifact manifests are part of this repository. The secret stand-ins catch math/indexing/conversion but cannot emulate Lua-client secret boolean evaluation; guard outputs, module API boundaries and concrete cases are checked separately. No game screenshots, combat log access, game-directory writes, local installation or real encounter tests were performed.
