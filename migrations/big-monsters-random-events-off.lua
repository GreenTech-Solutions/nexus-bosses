-- Big Monsters came to every game of razi-protocol 3.0 with nexus-bosses, and its random events (soldiers, the worm and
-- tree events, the silo attacks) started on the planets of the player, enemies on or off. The random events now follow
-- the map setting nexus-bosses-big-monsters-random-events (auto by default, scripts/nb_bm.lua), which this mod applies
-- in its on_configuration_changed. The silo attacks are a setting of Big Monsters, off by default now
-- (settings-updates.lua): a game that still has its old default gets the new one once, a value the player picked
-- stays. Big Monsters reads its settings again in its own on_configuration_changed, after the migrations.
local setting = settings.global["bm-enable-silo-attack"]
if setting and setting.value == true then
  settings.global["bm-enable-silo-attack"] = { value = false } -- luacheck: ignore 122 (the runtime API takes a new value this way)
  log("[nexus-bosses] bm-enable-silo-attack: true -> false")
end
