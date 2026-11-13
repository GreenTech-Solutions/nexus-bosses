-- The brood of the Last Commander (Big Monsters' BroodHumans) includes soldiers with atomic rockets while
-- bm-allow-nuker is on, its default. A trial should not end in a crater: off by default, the player can turn it back on.
local nuker = data.raw["bool-setting"]["bm-allow-nuker"]
if nuker then
  nuker.default_value = false
end

-- Big Monsters attacks every rocket silo when it is built and then every few days (bm-enable-silo-attack, on by default
-- there): on any surface where a player stands near the silo, without its list of planets, which is where the map
-- setting of this mod keeps its monsters (Hyarion, razi-protocol 3.1.3, 12.11.2026). A default does not reach a save
-- that has the setting on, and the setting is not this mod's to change at runtime, so it is off for good: hidden with a
-- forced value, as Big Monsters does with its own settings (settings-updates.lua).
local silo_attack = data.raw["bool-setting"]["bm-enable-silo-attack"]
if silo_attack then
  silo_attack.default_value = false
  silo_attack.hidden = true
  silo_attack.forced_value = false
end
