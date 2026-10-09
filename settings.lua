-- Settings of the mod. The startup ones change prototypes (health of the bosses, price of the beacons, what the trials
-- gate), the map ones are read while the game runs.
data:extend({
  {
    type = "double-setting",
    name = "nexus-bosses-boss-health",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.1,
    maximum_value = 10,
    order = "a",
  },
  {
    type = "double-setting",
    name = "nexus-bosses-beacon-cost",
    setting_type = "startup",
    default_value = 1,
    minimum_value = 0.1,
    maximum_value = 10,
    order = "b",
  },
  {
    type = "bool-setting",
    name = "nexus-bosses-gate-warp-drive",
    setting_type = "startup",
    default_value = true,
    order = "c",
  },
  {
    type = "int-setting",
    name = "nexus-bosses-countdown",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 30,
    maximum_value = 600,
    order = "a",
  },
  {
    type = "bool-setting",
    name = "nexus-bosses-big-monsters-elsewhere-off",
    setting_type = "runtime-global",
    default_value = true,
    order = "b",
  },
})
