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
| `Wardrobe` | buy/own/wear clothing that feeds `Disguise` | `buy`, `wear`, `worn_looks`, `worn_look`, `items_in_slot` | a wardrobe UI buys against the wallet; push `worn_looks()` into `Disguise.set_appearance` per slot so a change of clothes changes recognition |
| `PoliceEscalation` | response tier per star | `response_units`, `has_swat/helicopter/military`, `aggression`, `weapon_tier` | feed `PoliceSpawner`: pick the scene + count per `response_units(stars)` |
| `PursuitTactics` | chase tactics | `intercept_point`, `should_ram`, `pit_side`, `choose_tactic` | drive `Police`/traffic-cop movement when chasing |
| `GangTerritory` | turf control | `add_influence`, `take_over`, `controlled_fraction` | a per-district influence tracker + a turf-war trigger |
| `FactionStanding` | per-faction reputation (-100 hostile..+100 allied) | `adjust`, `tier_of`, `will_attack`, `will_assist`, `to_dict` | adjust on player actions (rivalry bleeds onto enemies); NPC AI reads `will_attack`/`will_assist`; faction ids align with `GangTerritory` |

## Combat

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `WeaponBallistics` | falloff / hit-zones / spread / recoil bloom | `effective_damage`, `spread_direction`, `Bloom` | apply in `WeaponController` when resolving a shot |
| `ExplosionModel` | radial damage + knockback + chain | `damage_at`, `knockback`, `should_chain`, `apply_to_many` | on grenade/vehicle blast, query nearby hittables |
| `MeleeCombat` | combos / block / counter / stamina | `strike`, `block_reduction`, `counter_damage` | drive `MeleeController` strikes + a stamina HUD |
| `CombatCover` | cover-point eval | `provides_cover`, `best_cover`, `peek_position`, `is_exposed` | give `CombatAi`/`Police` cover-seeking behaviour |
| `StealthDetection` | awareness meter | `update(can_see, vis, dt)`, `is_alerted`, `detection_speed` | per-NPC perception atop `CrimeWitness` FOV |
| `SoundPropagation` | the world's "ear": who hears a gunshot/alarm/engine, masked by distance + ambient | `base_loudness`, `is_alarming`, `perceived_intensity`, `is_audible`, `audible_radius`, `reaction_for`, `emit`, `loudest_heard`, `ambient_for` | the auditory complement to `StealthDetection` (visual). On a noisy event call `emit(src, kind, npc_listeners, ambient_for(base, is_night, rain01))`; for each `heard` listener seed `StealthDetection`, and on `ALARMED` promote via `CrimeWitness` / raise `WantedSystem` / spike `CrowdPanic` / dispatch `EmergencyServices`. `loudest_heard` picks what an idle NPC turns toward. Pure — no scene access |
| `FirePropagation` | spreading fire + fuel burnout | `ignite_intensity`, `update_fires`, `damage_per_second` | molotov/vehicle fire that spreads across flammables |
| `WeaponLoadout` | attachments (optic/muzzle/mag/grip) tune a weapon | `equip`, `mult_for`, `apply_mult`, `mag_size`, `is_suppressed` | a weapon-mod UI; apply `apply_mult(base, "spread"/"range"/"recoil")` around the `WeaponBallistics` calls, `mag_size` to ammo, `is_suppressed` to witness noise |

## Vehicles

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `VehicleHandling` | arcade grip/drift | `apply_friction`, `slip_angle`, `drift_factor`, `DriftScorer` | layer onto `Car`/`Bike` velocity each physics frame |
| `VehicleHealth` | damage -> fire -> wreck | `apply_damage`, `tick`, `state`, `just_exploded` | on car damage; trigger `ExplosionModel` on wreck |
| `VehicleCondition` | persistent per-vehicle fuel + engine/tire wear (the gas/mechanic loop) | `drive`, `apply_crash`, `refuel`, `service`, `condition`, `fuel_fraction`, `top_speed_factor`, `grip_factor` | a `Car` node owns one per active vehicle: each frame `drive(id, dist, intensity)` burns fuel + wears; `VehicleHealth` impacts feed `apply_crash`. HUD reads `fuel_fraction`/`condition`; `top_speed_factor` caps max-speed and `grip_factor` multiplies into `VehicleHandling`. A gas-station calls `refuel`, a mechanic `service`. **Produces the `condition` float `ChopShop.value()` consumes** (the seam nothing fed before). Persists via `to_dict`/`load_dict`. Pure |
| `VehicleModShop` | tiered upgrades -> stat multipliers | `upgrade`, `top_speed_multiplier`, `grip_multiplier` | a mod-garage trigger; multipliers feed `VehicleHandling` |
| `Carjacking` | yank a driver out | `can_reach`, `door_side`, struggle timer, `heat_for_jack` | player enter-vehicle path + `WantedTracker.report_crime` |
| `GarageStorage` | store/retrieve/impound vehicles | `store`, `retrieve`, `impound`, `recover_from_impound` | a garage trigger + saved vehicle list |
| `ChopShop` | fence a vehicle: class × condition × demand × heat | `value`, `deliver`, `set_requests`, `rotate_requests`, `total_earned` | a chop-shop trigger reads the car's class + `VehicleHealth.health_fraction()`, calls `deliver` and pays the wallet; rotate most-wanted orders for bonus pay |
| `Parachute` | freefall/deploy/land | `deploy`, `update_fall_speed`, `landing_impact` | player skydive state above a height threshold |

## Driving the world alive

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `PedestrianTraffic` | peds dodge cars / cross safely | `nearest_threat`, `dodge_velocity`, `safe_to_cross` | blend `dodge_velocity` into `Pedestrian` steering near traffic |
| `CrowdPanic` | gunfire panic ripples through a crowd | `initial_fear`, `update_crowd`, `flee_direction` | drive `CrowdDirector` peds on a scare event |
| `TrafficSignal` | junction light cycle + right-of-way | `tick`, `light_for`, `should_stop`, `yields_to` | place at intersections; gate `TrafficCar` at the stop line |
| `EmergencyServices` | ambulance/fire dispatch | `service_for`, `nearest_responder`, response timer | spawn a responder on a wreck/fire/injury incident |
| `WeatherEffects` | rain/fog gameplay impact | `grip_multiplier`, `visibility_range`, `ai_sight_multiplier` | feed `WeatherController` level into handling + detection |
| `AmbientEvents` | weighted freeroam encounters (mugging/race/heist) | `trigger_next`, `eligible_ids`, `can_fire`, `trigger` | a world director calls `trigger_next(rng, now, {stars, district})` on a timer and spawns the returned encounter; per-event cooldowns + a global gap prevent spam |

## Missions / activities

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `MissionChain` | campaign sequencing | `current`, `complete_current`, `is_campaign_complete` | wired live via `MissionCampaign` (5-mission arc in miami) |
| `MissionObjectiveTypes` | reach/collect/eliminate/escort/survive/defend | `*_satisfied`, `Counter` | use in `MissionController` for varied objectives |
| `SideJob` | taxi/delivery/vigilante contracts | `fare`, `payout`, active-job lifecycle | wired live via `SideJobBoard` (pickup/dropoff Area3Ds) |
| `StreetRace` | checkpoint laps + placement | `reached`, `progress`, `placement`, `reward` | checkpoint Area3Ds + rival progress feeds |
| `HeistCrew` | crew skill/cut -> odds + take | `add_member`, `success_chance`, `attempt`, `payout` | a heist-planning UI + a mission finale |
| `StuntScore` | freeform trick-combo scorer (air/near-miss) | `add_trick`, `multiplier`, `pending_score`, `bank`, `wipe` | a stunt controller calls `add_trick` on detected tricks, `bank` on a clean land / `wipe` on crash; apply `cash_for`/`respect_for` to wallet + `PlayerProgression` |
| `HitContract` | assassination board that moves the stock market | `available`, `accept`, `market_effect_of`, `complete`, `total_earned` | a contract board; on `complete()` feed the returned `market_effect` to `StockMarket.apply_rivalry_shock` (the invest-then-hit loop) |

## Economy / progression

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `ShopModel` | priced catalogue + purchase | `purchase`, `can_afford`, `sell_value` | a shop trigger + `PlayerStats.spend_money` |
| `PropertyOwnership` | buy properties + passive income | `buy`, `accrue`, `collect`, `daily_income` | property triggers + a daily income tick |
| `BusinessVenture` | own + OPERATE production businesses (supply→product→sell) — the active layer atop PropertyOwnership's passive income | `acquire`, `buy_supplies`, `accrue`, `hire`, `upgrade`, `production_rate`, `sale_price`, `sell`, `total_product` | a business-property trigger `acquire()`s against `PlayerStats.money`; a daily/world tick calls `accrue(delta_days)`; a "manage" UI calls `buy_supplies`/`hire`/`upgrade`; at cash-out pass `DistrictEconomy.desirability(district)` as `demand` and a `WantedSystem`/`FactionStanding`-derived 0..1 `heat` into `sale_price`/`sell`, then credit `proceeds`. Pure — wallet resolved by caller |
| `DistrictEconomy` | living real-estate: turf/crime move desirability | `desirability`, `property_value`, `income_multiplier`, `set_control`, `add_heat`, `invest` | feed `GangTerritory.influence_in` into `set_control` and crimes into `add_heat`; scale `PropertyOwnership` price/income by `desirability` |
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
| `NewsBulletin` | player deeds -> reactive radio/TV headlines | `report`, `next_bulletin`, `has_pending`, `recent` | `report` on crimes/heists/escapes (severity-tiered); when `RadioScheduler` yields a NEWS segment, read `next_bulletin()` for the anchor line |
| `ContactServices` | call a contact for a favour (lower-wanted/mechanic/backup) | `request`, `can_use`, `cooldown_remaining`, `is_ready` | the phone UI gates `request` with `PhoneContacts.will_answer`, charges the wallet, and triggers the effect by `kind`; cost + cooldown per service |
| `MusicDirector` | dynamic score intensity (calm→tension→combat→chase) | `update`, `current_tier`, `current_stem`, `is_intense` | an audio node calls `update({stars, in_combat, in_chase}, dt)` each frame and crossfades to `current_stem()`; escalates instantly, de-escalates on a hold |
| `SwimStamina` | oxygen/stamina/drowning | `update`, `is_drowning`, `swim_speed`, `drown_damage` | the meter layer above the swim motion node |
| `LootTable` | weighted seeded drops | `roll`, `roll_many`, `drop_chance_satisfied` | on enemy death / crate smash -> pickups |
| `CharacterRoster` | dual-protagonist switching + per-lead state | `switch_to`, `can_switch`, `active`, `money_of`, `position_of`, `to_dict` | load the active lead's wallet/wanted/position into PlayerStats + world on `switch_to`; write it back before switching away |

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

`MarketEventCoordinator` is a ready-to-drop self-wiring node (cf. PaySprayShop):
it owns a `StockMarket`, subscribes to the `wanted` group's `stars_changed` to
rally defense stocks on a crime spree, and applies `HitContract` effects via
`apply_hit_effect`. Its node-level wiring is CI-gated headless by
`tests/market_event_probe.gd` (a mock tree, no scene file). Adding it to
`miami.tscn` is the remaining step to make the stock-market loop live in play.

`CrimeReactionDirector` is its sibling on the same `wanted` hook: it owns a
`NewsBulletin` + `DistrictEconomy` and, on a wanted spike, files a severity-scaled
headline and heats the active district (which cools over time via `_process`). The
two directors split the signal cleanly — market vs news+real-estate — so both can
sit in the scene. CI-gated headless by `tests/crime_reaction_probe.gd`.

`CharacterSwitcher` owns a `CharacterRoster` and syncs each lead's wallet through
the live `player_stats` node on `request_switch()` (write the current wallet back,
load the incoming lead's), so per-character money persists across switches. CI-gated
headless by `tests/character_switch_probe.gd`.

`AmbientEventDirector` drives `AmbientEvents` on a timer: each tick it builds
`{stars (from the wanted group), district}`, rolls `trigger_next`, and emits
`encounter_triggered(id, kind)` for the scene to spawn. CI-gated headless by
`tests/ambient_event_probe.gd`.
