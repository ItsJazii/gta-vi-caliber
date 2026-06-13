# Build Order: the front door

**Read this first.** It answers two questions the other docs spread across
several files: *where are we right now*, and *what gets built next, in what
order*. It does not replace anything. It points at the canonical docs and keeps
an honest, dependency-ordered position on top of them.

| Canonical doc | What it owns |
| --- | --- |
| [`../plan.md`](../plan.md) | Strategy: the experiment, Phases A to H, the cut line, the honest scope. |
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | How to build: the two-layer model, the native-code golden rule, conventions, the frame budget. |
| [`SYSTEMS.md`](SYSTEMS.md) | The parts bin: every gameplay system, its API, how to wire it, and which are already wired. **Source of truth for wired vs shelf.** |
| [`ROADMAP.md`](ROADMAP.md) | The forward task board (M0 to M6). Its checkboxes lag the code; trust this file for current state. |

---

## The dependency ladder

Each layer rests on the one below it. The rule is simple and it is the thing the
merge history keeps violating: **do not invest in an upper layer's polish before
the layer beneath it holds.** Building content volume before streaming is proven
means authoring a map you cannot stream; wiring economy systems before the
foundation is clean means building on sand.

```
L6  Polish & ship        GI, ocean v2, perf lockdown, trailer, 1.0      Phase G/H
L5  Play loop & story     mission depth + a narrative spine              Phase F + Track N   (long pole)
L4  Life & atmosphere     crowd/traffic/weather density, reactions       Phase E
L3  Content volume        many districts, a full campaign                Phase D             (long pole)
L2  Systems wired         SYSTEMS.md parts wired into the live world     Phase C / M5
L1  World substrate       streaming + floating origin at CITY scale      Phase B / M3
L0  Foundation            green gate, one canonical scene, a player      Phase A
        parallel, continuous: Track Q (fidelity)  +  Engine track (worldcore, evidence-driven)
```

The two long poles, content volume (L3) and narrative/audio (L5 / Track N), each
take longer than every engineering layer combined. Plan time and people around
them, not around the fast layers.

---

## You are here

Between **L1 and L2**. A vertical slice exists; the breadth above it does not.

**Solid:**
- `miami.tscn` is the one canonical playable loop, each step guarded by a runtime
  probe in `tools/check.sh`: player health/stats, crime to wanted to police
  dispatch, a 5-mission campaign, pay-n-spray, the busted/arrest fail loop,
  crowd/traffic/police directors, NPC barks.
- 167 unit-test files. `gdUnit4` vendored and running. Gate green on a clean clone.
- Interaction layer landed (context-sensitive interact key, generic
  `interactables` contract) and building entry on top of it (street doors, fade
  transition into a footprint-built interior).

**L0 Foundation, nearly done, loose ends (Phase A):** land the Vice City pivot
fully (retire legacy `los_angeles_*`/demo scenes), `main_menu` Play straight into
`miami.tscn`, gamepad **button** bindings + a rebindable-input persistence layer,
and route the premium cinematic lighting in behind a quality setting.

**L1 World substrate, partial and the real bottleneck:** a GDScript tile
streamer and floating origin exist, but city-scale streaming is **not proven**,
and the native `worldcore` accelerators (async streamer, impostor baker) are
written but unwired (they ship as `worldcore.gdextension.example`). Until this
layer holds, L3 content volume cannot start.

**L2 Systems wired, about a quarter done:** roughly 10 of ~40 systems in
`SYSTEMS.md` are wired (the wanted/police/mission/pay-spray/arrest loop and its
self-wiring coordinators). The rest are **built, tested, and on the shelf** :
verified zero live consumers for `CasinoGames`, `HeistCrew`, `ContrabandMarket`,
`TrafficSignal`, `EmergencyServices`, `FirePropagation`, `GangTerritory`,
`PedestrianTraffic`, `GpsNavigation`, `LootTable`, `GarageStorage`, and more.
Wiring these is the bulk of the near-term work and most of it needs no streaming.

**L3 to L6, not meaningfully started**, beyond Ocean v1, day/night, and the
cinematic capture tooling that lives in the atmosphere/polish layers.

---

## What to build next, in order

### 1. Close the foundation (L0 / Phase A)
Everything rests on it, so finish it before widening. Land the pivot, wire
`main_menu` to `miami.tscn`, add gamepad button bindings and rebind persistence,
and gate the cinematic lighting in for the dense district with a measured budget.
See `plan.md` Phase A for the exact list.

### 2. Wire the parts bin (L2 / Phase C): needs no streaming, so do it now
Ordered by dependency, each wired with the `SYSTEMS.md` self-wiring-coordinator
pattern and a runtime probe (repo rule: no probe, it does not count):

1. **Interaction-dependent economy and world objects**: these plug straight
   into the interaction contract and building entry that just landed, so they are
   the natural continuation of the current thread: `ShopModel`,
   `PropertyOwnership`, `GarageStorage`, `VehicleModShop`, `CasinoGames`,
   `ContrabandMarket`.
2. **World-life systems** that make the one district feel inhabited:
   `TrafficSignal`, `PedestrianTraffic`, `EmergencyServices`, deeper `CrowdPanic`,
   `FirePropagation`.
3. **Combat depth:** `CombatCover`, `StealthDetection`, `PursuitTactics`,
   `MeleeCombat`.
4. **Activities:** `StreetRace`, `HeistCrew` (`SideJob` is already wired).
5. **Support polish:** `GpsNavigation` into the minimap, `LootTable` on
   death/crates, `RadioScheduler` programming for vehicle radio.

### 3. Prove streaming at city scale (L1 / Phase B / M3): in parallel, the bottleneck
This is what gates content volume. Build it GDScript-first; the native
`worldcore` modules earn their place only with a captured profile, per the
`ARCHITECTURE.md` golden rule. Do not start L3 content volume until a 4 km
drive/walk streams with no hitch.

### 4. Continuous, never blocking
Track Q fidelity passes and the engine track run alongside, not as gates.

---

## Why this exists (and what it cannot fix)

The strategy, architecture, and systems catalogue were already strong; what was
missing was a single honest front door and a dependency order, so contributors
and agents defaulted to merging whatever, wherever. This doc is that front door.

A document cannot enforce coordination, though. The merge soup is also a process
issue, and the fix for that already lives in `plan.md` §4: lane discipline, one
concern per PR, and routing shared-file changes (`project.godot`, `player.gd`,
shared scenes) through an integrator. This file only makes the target legible.

**Maintenance rule:** when a PR changes the state described here, it updates this
file in the same PR. A front door that drifts is worse than none.
