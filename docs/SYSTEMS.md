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
| `Disguise` | change your look to lose the heat | `set_appearance`, `log_sighting`, `recognition`, `evasion_speedup`, `changed_slots` | **live on the player** via `DisguiseTracker` (group `player_disguise`): `WardrobeShop` pushes worn looks into it, and `WantedEvasionController` scales unseen search delta by `evasion_speedup()` once police have a description. CI-guarded by `tests/wardrobe_disguise_probe.gd` + `tests/disguise_evasion_probe.gd`. TODO: call `log_sighting()` from witness/cop perception |
| `Wardrobe` | buy/own/wear clothing that feeds `Disguise` | `buy`, `wear`, `worn_looks`, `worn_look`, `items_in_slot` | **wired live** via `WardrobeShop` (Node3D, group `interactables`): press interact at the storefront to buy + wear an outfit against `PlayerStats`; worn looks now update the live `DisguiseTracker`. CI-guarded by `tests/wardrobe_shop_probe.gd` + `tests/wardrobe_disguise_probe.gd` |
| `PoliceEscalation` | response tier per star | `response_units`, `has_swat/helicopter/military`, `aggression`, `weapon_tier` | feed `PoliceSpawner`: pick the scene + count per `response_units(stars)` |
| `PursuitTactics` | chase tactics | `intercept_point`, `should_ram`, `pit_side`, `choose_tactic` | drive `Police`/traffic-cop movement when chasing |
| `GangTerritory` | turf control | `add_influence`, `take_over`, `controlled_fraction` | **surfaced to the player** via `TurfClaim` (Node3D, group `interactables`): a walk-up claim point where you spend cash to buy influence in a district and take it over at full influence. CI-guarded by `tests/turf_claim_probe.gd`. TODO: a district-wide influence tracker + visible turf-war state |
| `FactionStanding` | per-faction reputation (-100 hostile..+100 allied) | `adjust`, `tier_of`, `will_attack`, `will_assist`, `to_dict` | `TurfClaim` calls `adjust()` on the rival crew when you muscle into their turf; NPC AI still reads `will_attack`/`will_assist`; faction ids align with `GangTerritory` |

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
| `GarageStorage` | store/retrieve/impound vehicles | `store`, `retrieve`, `impound`, `recover_from_impound` | **wired live** via `GarageStorageTrigger` (Node3D, group `interactables`): drive a car into the `StoreZone` Area3D to park it (hidden + reparented out of the world, remembered by `store()`); press interact at the garage to `retrieve()` the most-recently parked car back to the door (same node, optional fee to `PlayerStats`). CI-guarded by `tests/garage_storage_probe.gd`. TODO: surface `impound`/`recover_from_impound` for cars abandoned while wanted + a HUD garage list |
| `ChopShop` | fence a vehicle: class × condition × demand × heat | `value`, `deliver`, `set_requests`, `rotate_requests`, `total_earned` | **wired live** via `ChopShopTrigger` (Node3D, group `chop_shop`): drive a car into its `FenceZone` Area3D and it's stripped — priced by class (inferred from the car's scene) × condition (`Car.health/max_health`) × demand, paid to `PlayerStats`, then the car is removed. CI-guarded by `tests/chop_shop_probe.gd`. TODO: rotate most-wanted orders for the demand bonus + a heat discount off `WantedTracker` |
| `Parachute` | freefall/deploy/land | `deploy`, `update_fall_speed`, `landing_impact` | player skydive state above a height threshold |

## Driving the world alive

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `PedestrianTraffic` | peds dodge cars / cross safely | `nearest_threat`, `dodge_velocity`, `safe_to_cross` | blend `dodge_velocity` into `Pedestrian` steering near traffic |
| `CrowdPanic` | gunfire panic ripples through a crowd | `initial_fear`, `update_crowd`, `flee_direction` | **wired live** via `CrowdPanicDirector` (Node): hooks `WeaponController.crime_committed` (group `weapon_controller`) and on a shooting calls `Pedestrian.scare()` on every ped within `scare_radius` (fear falloff from `initial_fear`). CI-guarded by `tests/crowd_panic_probe.gd`. TODO: panic contagion via `propagated_fear`, + spike on explosions |
| `TrafficSignal` | junction light cycle + right-of-way | `tick`, `light_for`, `should_stop`, `yields_to` | place at intersections; gate `TrafficCar` at the stop line |
| `EmergencyServices` | ambulance/fire dispatch | `service_for`, `nearest_responder`, `should_dispatch`, `eta`, response timer | **wired live** via `ResponderDispatcher` (Node): group-polls `weapon_controller`, and on a player kill rolls out an ambulance that drives in, treats the scene, and clears. CI-guarded by `tests/responder_dispatcher_probe.gd`. TODO: WRECK/FIRE incidents off `VehicleHealth.just_exploded`, + a visible on-scene treat dwell |
| `WeatherEffects` | rain/fog gameplay impact | `grip_multiplier`, `visibility_range`, `ai_sight_multiplier`, `ai_sight_range` | `WeatherController` exposes normalized wetness/fog, and `Police` now shortens spotting range in heavy rain/fog. TODO: feed wetness into vehicle grip/traffic speed |
| `AmbientEvents` | weighted freeroam encounters (mugging/race/heist) | `trigger_next`, `eligible_ids`, `can_fire`, `trigger` | a world director calls `trigger_next(rng, now, {stars, district})` on a timer and spawns the returned encounter; per-event cooldowns + a global gap prevent spam |

## Missions / activities

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `MissionChain` | campaign sequencing | `current`, `complete_current`, `is_campaign_complete` | wired live via `MissionCampaign` (5-mission arc in miami) |
| `MissionObjectiveTypes` | reach/collect/eliminate/escort/survive/defend | `*_satisfied`, `Counter` | use in `MissionController` for varied objectives |
| `SideJob` | taxi/delivery/vigilante contracts | `fare`, `payout`, active-job lifecycle | wired live via `SideJobBoard` (pickup/dropoff Area3Ds) |
| `StreetRace` | checkpoint laps + placement | `reached`, `progress`, `placement`, `reward` | **wired live** via `RaceController` (Node3D, group `race`): ordered child `Marker3D` checkpoints, pass within `checkpoint_radius` in order to finish a lap, finishing pays `reward`. CI-guarded by `tests/race_probe.gd`. TODO: rival drivers + a longer road circuit + a HUD progress/checkpoint readout |
| `HeistCrew` | crew skill/cut -> odds + take | `add_member`, `success_chance`, `attempt`, `payout` | **surfaced to the player** via `HeistPlanningBoard` (Node3D, group `interactables`): each press recruits the next crew member (charged to `PlayerStats`); once staffed, a press pulls the job — a win banks the player's crew-adjusted share, a loss pays nothing, then the crew resets. CI-guarded by `tests/heist_planning_board_probe.gd`. TODO: pick-your-crew UI + a real heist mission finale |
| `StuntScore` | freeform trick-combo scorer (air/near-miss) | `add_trick`, `multiplier`, `pending_score`, `bank`, `wipe` | a stunt controller calls `add_trick` on detected tricks, `bank` on a clean land / `wipe` on crash; apply `cash_for`/`respect_for` to wallet + `PlayerProgression` |
| `HitContract` | assassination board that moves the stock market | `available`, `accept`, `market_effect_of`, `complete`, `total_earned` | **wired live** via `HitContractBoard` (Node3D, group `interactables`): accept the next market-moving contract, press again to complete the hit — pays the `reward` to `PlayerStats` and best-effort feeds the `market_effect` to the live `MarketEventCoordinator` (`apply_hit_effect`) so the kill shocks `StockMarket` (the invest-then-hit loop, pairs with `BrokerageTerminal`). CI-guarded by `tests/hit_contract_board_probe.gd`. TODO: a go-to-target objective + an active-hit HUD |

## Economy / progression

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `ShopModel` | priced catalogue + purchase | `purchase`, `can_afford`, `sell_value` | a shop trigger + `PlayerStats.spend_money` |
| `PropertyOwnership` | buy properties + passive income | `buy`, `accrue`, `collect`, `daily_income` | property triggers + a daily income tick |
| `BusinessVenture` | own + OPERATE production businesses (supply→product→sell) — the active layer atop PropertyOwnership's passive income | `acquire`, `buy_supplies`, `accrue`, `hire`, `upgrade`, `production_rate`, `sale_price`, `sell`, `total_product` | **wired live** via `BusinessVentureHub` (Node3D, group `interactables`): first interact `acquire()`s against `PlayerStats.money` + stocks supplies, the node `accrue()`s product in `_process` between visits, and a later interact `sell()`s the stockpile and banks `proceeds`. CI-guarded by `tests/business_venture_hub_probe.gd`. TODO: a "manage" UI for `hire`/`upgrade`, and feed real `DistrictEconomy.desirability` as `demand` + a `WantedSystem` 0..1 `heat` into the cash-out |
| `DistrictEconomy` | living real-estate: turf/crime move desirability | `desirability`, `property_value`, `income_multiplier`, `set_control`, `add_heat`, `invest` | feed `GangTerritory.influence_in` into `set_control` and crimes into `add_heat`; scale `PropertyOwnership` price/income by `desirability` |
| `ContrabandMarket` | buy-low/sell-high arbitrage | `price_in`, `buy`, `sell`, `best_market`, `bust_risk` | **wired live** via `ContrabandDealer` (Node3D, group `contraband_dealer`): a DealZone Area3D buys, a FenceZone Area3D in a dearer district sells. `bust_risk` is now **surfaced on police proximity** — `resolve_fence_sale()` voids the payout and raises wanted heat (group `wanted`) when cops are near the fence at sell time, scaling with deal size and how many/how close. CI-guarded by `tests/contraband_market_probe.gd` + `tests/contraband_bust_probe.gd`. TODO: a price-board UI |
| `CasinoGames` | roulette/slots/blackjack | `roulette_spin`, `roulette_payout`, `slot_payout`, `blackjack_settle`, `hand_value`, `dealer_should_hit`, bankroll | **slots + roulette + blackjack wired live**: `SlotMachine`, `RouletteTable`, and `BlackjackTable` (all Node3D, group `interactables`) — press interact to bet + play a round, paying/charging `PlayerStats`. CI-guarded by `tests/slot_machine_probe.gd` + `tests/roulette_table_probe.gd` + `tests/blackjack_table_probe.gd`. TODO: a reel/wheel/card-result HUD |
| `PlayerProgression` | respect/XP + unlocks | `add_xp`, `level`, `unlocks_at`, `is_unlocked` | wired live via `ProgressionTracker` (missions grant XP) |
| `PlayerSkills` | activity-based proficiency (drive/shoot/stamina...) | `train`, `level`, `tier`, `bonus`, `overall_mastery`, `to_dict` | **wired live** via `SkillsCoordinator` (code-spawned under `Player`, group `player_skills`): walking distance trains stamina, driven-vehicle distance trains driving, and confirmed weapon hits train shooting. `SaveManager` persists it as `player_skills`. CI-guarded by `tests/unit/test_skills_coordinator.gd` + `tests/unit/test_save_manager_player_skills.gd` |
| `StatTracker` | lifetime stats + 100% | `add`, `is_achieved`, `completion_percent`, serialize | wired live via `StatsCoordinator`; persisted by `SaveManager` as `lifetime_stats` |
| `StockMarket` | event-driven equities + tracked portfolio | `apply_rivalry_shock`, `apply_sector_event`, `price`, `buy`, `sell`, `unrealized_gain` | **surfaced to the player** via `BrokerageTerminal` (Node3D, group `interactables`): a walk-up terminal that trades the world's ONE LIVE `StockMarket` — the one owned by `MarketEventCoordinator` that `HitContractBoard` shocks and wanted spikes rally (it no longer drifts a private copy). First press buys a lot, a later press sells for realized P&L against `PlayerStats`, so a completed assassination or a wanted spike moves what the brokerage sells for — the invest → take-the-hit → cash-out loop is closed end to end. CI-guarded by `tests/brokerage_terminal_probe.gd`. TODO: a multi-company trade UI |

## Support

| System | Purpose | Key API | Wiring |
|---|---|---|---|
| `GpsNavigation` | route progress/ETA/next-turn | `distance_remaining`, `progress`, `next_turn`, `has_arrived` | **wired live** via `GpsRouteCoordinator` (code-spawned under `Minimap`, group `gps_route`): active objective waypoints feed `Minimap.set_gps_route()` with a NavGrid-backed route when a live traffic/crowd/city director has one, then fall back to the minimap's direct waypoint line when no route is available. CI-guarded by `tests/unit/test_gps_route_coordinator.gd` |
| `RadioScheduler` | song/DJ/ad/news programming | `next_segment`, `pick_song`, `advance` | bridged by `RadioNewsDirector`: advances the station program and emits a line for songs/DJ/ads/IDs/NEWS. `RadioReadout` on the gameplay HUD subscribes to those lines and to `VehicleRadio.now_playing_changed`, so station/news text is visible to the player. CI-guarded by `tests/radio_news_probe.gd` |
| `NewsBulletin` | player deeds -> reactive radio/TV headlines | `report`, `next_bulletin`, `has_pending`, `recent` | `CrimeReactionDirector` reports crimes; `RadioNewsDirector` finds that queue and drains `next_bulletin()` when `RadioScheduler` yields a NEWS slot. CI-guarded by `tests/radio_news_probe.gd` |
| `ContactServices` | call a contact for a favour (lower-wanted/mechanic/backup) | `request`, `can_use`, `cooldown_remaining`, `is_ready` | wired into the live `Phone`: connected service contacts charge `PlayerStats`, emit `service_requested`, the heat service clears `WantedTracker`, and the mechanic repairs the current driven vehicle. CI-guarded by `tests/phone_contact_services_probe.gd` + `tests/phone_mechanic_probe.gd`. TODO: map weapons/transport/combat signals to actual spawns |
| `MusicDirector` | dynamic score intensity (calm→tension→combat→chase) | `update`, `current_tier`, `current_stem`, `is_intense` | an audio node calls `update({stars, in_combat, in_chase}, dt)` each frame and crossfades to `current_stem()`; escalates instantly, de-escalates on a hold |
| `SwimStamina` | oxygen/stamina/drowning | `update`, `is_drowning`, `swim_speed`, `drown_damage` | the meter layer above the swim motion node |
| `LootTable` | weighted seeded drops | `roll`, `roll_many`, `drop_chance_satisfied` | **wired live** via `LootDropDirector` (Node, group `loot_drop`): hooks `WeaponController.crime_committed` and on a kill spawns a `Pickup` (medkit/armor) at the kill site; `LootCrate` props use the same combat `take_damage()` contract and call `drop_from_crate()` when smashed. CI-guarded by `tests/loot_drop_probe.gd` + `tests/unit/test_loot_crate.gd`. TODO: cash/ammo pickup kinds |
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

`MarketEventCoordinator` is **wired live in `miami.tscn`** (self-wiring node, cf.
PaySprayShop): it owns a `StockMarket`, subscribes to the `wanted` group's
`stars_changed` to rally defense stocks on a crime spree, and applies
`HitContract` effects via `apply_hit_effect`. Node logic is CI-gated headless by
`tests/market_event_probe.gd` (a mock tree); the live in-scene connection is
asserted by `tests/miami_wiring_probe.gd`. Remaining to surface to the player: a
brokerage/ticker UI reading its public `market`.

`CrimeReactionDirector` is its sibling on the same `wanted` hook and is **wired
live in `miami.tscn`** too: it owns a `NewsBulletin` + `DistrictEconomy` and, on a
wanted spike, files a severity-scaled headline and heats the active district
(which cools over time via `_process`). The two directors split the signal cleanly
— market vs news+real-estate. Node logic CI-gated by `tests/crime_reaction_probe.gd`;
live connection asserted by `tests/miami_wiring_probe.gd`. `RadioNewsDirector`
now joins group `radio_news`, finds this director through group `crime_reaction`,
and drains `news.next_bulletin()` into a scheduled NEWS slot. `RadioReadout` in
`game_hud.tscn` subscribes to those program lines and vehicle-radio now-playing
updates, so the station/news line has a player-facing HUD surface. Scene-free
bridge + HUD readout are CI-gated by `tests/radio_news_probe.gd`.

`CharacterSwitcher` owns a `CharacterRoster` and syncs each lead's wallet through
the live `player_stats` node on `request_switch()` (write the current wallet back,
load the incoming lead's), so per-character money persists across switches. CI-gated
headless by `tests/character_switch_probe.gd`.

`AmbientEventDirector` is **wired live in `miami.tscn`**: on a timer it builds
`{stars (from the wanted group), district}`, rolls `trigger_next`, and emits
`encounter_triggered(id, kind)`. Node logic CI-gated headless by
`tests/ambient_event_probe.gd`; live in-scene connection asserted by
`tests/miami_wiring_probe.gd`. Remaining to make encounters appear: connect
`encounter_triggered` to scene spawn logic (mugging/race/heist actors).
