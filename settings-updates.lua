-- The brood of the Last Commander (Big Monsters' BroodHumans) includes soldiers with atomic rockets while
-- bm-allow-nuker is on, its default. A trial should not end in a crater: off by default, the player can turn it back on.
local nuker = data.raw["bool-setting"]["bm-allow-nuker"]
if nuker then
  nuker.default_value = false
end

-- Big Monsters attacks every rocket silo when it is built and then every few days (bm-enable-silo-attack, default on);
-- unlike its other random events this does not go through its list of planets, so the random events setting of this
-- mod does not stop it. Off by default, the player can turn it back on.
local silo_attack = data.raw["bool-setting"]["bm-enable-silo-attack"]
if silo_attack then
  silo_attack.default_value = false
end
