-- The brood of the Last Commander (Big Monsters' BroodHumans) includes soldiers with atomic rockets while
-- bm-allow-nuker is on, its default. A trial should not end in a crater: off by default, the player can turn it back on.
local nuker = data.raw["bool-setting"]["bm-allow-nuker"]
if nuker then
  nuker.default_value = false
end
