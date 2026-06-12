# Gameplay Systems Reference

A catalogue of the pure, unit-tested simulation systems that make up the GTA-style
gameplay layer, with their purpose, key API, and **how to wire each into a live
scene**. Every system here is a `class_name` you can `ClassName.new()` (stateful)
or call statically (pure helpers); all are headless unit-tested under
`game/tests/unit/test_*.gd`.

Most systems follow one of two repo patterns:

- **Pure model + thin node**: the math lives in a `RefCounted` model; a `Node`
  reads it and drives the engine (see `WantedTracker` wrapping `WantedSystem`).
- **Self-wiring coordinator**: a small `Node` that finds collaborators by group
  in `_ready`/`_process` and needs no per-scene plumbing (see `MissionReward`,
  `ProgressionTracker`, `StatsCoordinator`, `WantedEvasionController`,
  `PaySprayShop`). This is the lowest-friction way to wire a model into a scene.

Groups the live scene already publishes: `player`, `player_health`,
`player_stats`, `wanted`, `mission`, `police`, `stats`, `progression`, `world`,
`spawn_points`.

---

## Wanted / law enforcement

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `WantedSystem` | heat -> stars core | `add_crime`, `stars`, `is_wanted`, `tick` | wrapped by `WantedTracker` (group `wanted`) |
| `CrimeWitness` | a crime only raises heat if seen | `can_witness`, `count_witnesses`, `heat_for_crime`, report timer | gate `WantedTracker._on_crime` on `count_witnesses(crime_pos, peds)` before adding heat |
| `WantedEvasion` | "go cold" search timer | `update(seen, dt)`, `is_cold`, `search_progress` | wired live via `WantedEvasionController` (raycasts cop LOS) |
| `PaySpray` | respray/hideout instant clear | `cost_for`, `is_seen_entering`, instance respray timer | wired live via `PaySprayShop` Area3D (group `pay_spray`) |
| `Disguise` | change your look to lose the heat | `set_appearance`, `log_sighting`, `recognition`, `evasion_speedup`, `changed_slots` | `log_sighting` when the player is spotted; scale the `WantedEvasion` search delta by `evasion_speedup()` so a disguised player goes cold faster |
| `PoliceEscalation` | response tier per star | `response_units`, `has_swat/helicopter/military`, `aggression`, `weapon_tier` | feed `PoliceSpawner`: pick the scene + count per `response_units(stars)` |
| `PursuitTactics` | chase tactics | `intercept_point`, `should_ram`, `pit_side`, `choose_tactic` | drive `Police`/traffic-cop movement when chasing |
| `GangTerritory` | turf control | `add_influence`, `take_over`, `controlled_fraction` | a per-district influence tracker + a turf-war trigger |

## Combat

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `WeaponBallistics` | falloff / hit-zones / spread / recoil bloom | `effective_damage`, `spread_direction`, `Bloom` | apply in `WeaponController` when resolving a shot |
| `ExplosionModel` | radial damage + knockback + chain | `damage_at`, `knockback`, `should_chain`, `apply_to_many` | on grenade/vehicle blast, query nearby hittables |
| `MeleeCombat` | combos / block / counter / stamina | `strike`, `block_reduction`, `counter_damage` | drive `MeleeController` strikes + a stamina HUD |
| `CombatCover` | cover-point eval | `provides_cover`, `best_cover`, `peek_position`, `is_exposed` | give `CombatAi`/`Police` cover-seeking behaviour |
| `StealthDetection` | awareness meter | `update(can_see, vis, dt)`, `is_alerted`, `detection_speed` | per-NPC perception atop `CrimeWitness` FOV |
| `FirePropagation` | spreading fire + fuel burnout | `ignite_intensity`, `update_fires`, `damage_per_second` | molotov/vehicle fire that spreads across flammables |

## Vehicles

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `VehicleHandling` | arcade grip/drift | `apply_friction`, `slip_angle`, `drift_factor`, `DriftScorer` | layer onto `Car`/`Bike` velocity each physics frame |
| `VehicleHealth` | damage -> fire -> wreck | `apply_damage`, `tick`, `state`, `just_exploded` | on car damage; trigger `ExplosionModel` on wreck |
| `VehicleModShop` | tiered upgrades -> stat multipliers | `upgrade`, `top_speed_multiplier`, `grip_multiplier` | a mod-garage trigger; multipliers feed `VehicleHandling` |
| `Carjacking` | yank a driver out | `can_reach`, `door_side`, struggle timer, `heat_for_jack` | player enter-vehicle path + `WantedTracker.report_crime` |
| `GarageStorage` | store/retrieve/impound vehicles | `store`, `retrieve`, `impound`, `recover_from_impound` | a garage trigger + saved vehicle list |
| `Parachute` | freefall/deploy/land | `deploy`, `update_fall_speed`, `landing_impact` | player skydive state above a height threshold |

## Driving the world alive

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `PedestrianTraffic` | peds dodge cars / cross safely | `nearest_threat`, `dodge_velocity`, `safe_to_cross` | blend `dodge_velocity` into `Pedestrian` steering near traffic |
| `CrowdPanic` | gunfire panic ripples through a crowd | `initial_fear`, `update_crowd`, `flee_direction` | drive `CrowdDirector` peds on a scare event |
| `TrafficSignal` | junction light cycle + right-of-way | `tick`, `light_for`, `should_stop`, `yields_to` | place at intersections; gate `TrafficCar` at the stop line |
| `EmergencyServices` | ambulance/fire dispatch | `service_for`, `nearest_responder`, response timer | spawn a responder on a wreck/fire/injury incident |
| `WeatherEffects` | rain/fog gameplay impact | `grip_multiplier`, `visibility_range`, `ai_sight_multiplier` | feed `WeatherController` level into handling + detection |

## Missions / activities

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `MissionChain` | campaign sequencing | `current`, `complete_current`, `is_campaign_complete` | wired live via `MissionCampaign` (5-mission arc in miami) |
| `MissionObjectiveTypes` | reach/collect/eliminate/escort/survive/defend | `*_satisfied`, `Counter` | use in `MissionController` for varied objectives |
| `SideJob` | taxi/delivery/vigilante contracts | `fare`, `payout`, active-job lifecycle | wired live via `SideJobBoard` (pickup/dropoff Area3Ds) |
| `StreetRace` | checkpoint laps + placement | `reached`, `progress`, `placement`, `reward` | checkpoint Area3Ds + rival progress feeds |
| `HeistCrew` | crew skill/cut -> odds + take | `add_member`, `success_chance`, `attempt`, `payout` | a heist-planning UI + a mission finale |
| `HitContract` | assassination board that moves the stock market | `available`, `accept`, `market_effect_of`, `complete`, `total_earned` | a contract board; on `complete()` feed the returned `market_effect` to `StockMarket.apply_rivalry_shock` (the invest-then-hit loop) |

## Economy / progression

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `ShopModel` | priced catalogue + purchase | `purchase`, `can_afford`, `sell_value` | a shop trigger + `PlayerStats.spend_money` |
| `PropertyOwnership` | buy properties + passive income | `buy`, `accrue`, `collect`, `daily_income` | property triggers + a daily income tick |
| `ContrabandMarket` | buy-low/sell-high arbitrage | `price_in`, `buy`, `sell`, `best_market`, `bust_risk` | district price boards + a carried-inventory risk |
| `CasinoGames` | roulette/slots/blackjack | `roulette_payout`, `slot_payout`, `blackjack_settle`, bankroll | a casino UI vs `PlayerStats` chips |
| `PlayerProgression` | respect/XP + unlocks | `add_xp`, `level`, `unlocks_at`, `is_unlocked` | wired live via `ProgressionTracker` (missions grant XP) |
| `PlayerSkills` | activity-based proficiency (drive/shoot/stamina...) | `train`, `level`, `tier`, `bonus`, `overall_mastery`, `to_dict` | call `train` from the matching activity (distance driven, shots landed); read `bonus(id)` to scale recoil/grip/sprint; persist via the save system |
| `StatTracker` | lifetime stats + 100% | `add`, `is_achieved`, `completion_percent`, serialize | wired live via `StatsCoordinator` |
| `StockMarket` | event-driven equities + tracked portfolio | `apply_rivalry_shock`, `apply_sector_event`, `price`, `buy`, `sell`, `unrealized_gain` | a brokerage/phone-app UI vs `PlayerStats`; feed mission kills, heists & district turf changes in as price shocks (the assassinate-a-rival-to-pump-the-stock loop) |

## Support

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `GpsNavigation` | route progress/ETA/next-turn | `distance_remaining`, `progress`, `next_turn`, `has_arrived` | feed a NavGrid route into the minimap GPS line |
| `RadioScheduler` | song/DJ/ad/news programming | `next_segment`, `pick_song`, `advance` | program a `VehicleRadio` station |
| `SwimStamina` | oxygen/stamina/drowning | `update`, `is_drowning`, `swim_speed`, `drown_damage` | the meter layer above the swim motion node |
| `LootTable` | weighted seeded drops | `roll`, `roll_many`, `drop_chance_satisfied` | on enemy death / crate smash -> pickups |

---

## Already wired & CI-guarded in `miami.tscn`

The playable map runs the full loop, each gated by a runtime probe in
`tools/check.sh`: player health/stats/wanted/mission/bark + crowd/traffic/police
directors (`miami_wiring_probe`), crime -> wanted -> police dispatch
(`miami_loop_probe`), the 5-mission campaign paying money/respect/stats
(`miami_mission_probe`), pay-n-spray wanted-clear (`miami_payspray_probe`), and
the busted/arrest fail-loop (`miami_arrest_probe`). `WantedEvasionController`,
`MissionReward`, `ProgressionTracker`, `StatsCoordinator`, `MissionCampaign`,
`PaySprayShop`, and `SideJobBoard` are the self-wiring coordinators already in the
scene — copy their shape to wire the rest.
