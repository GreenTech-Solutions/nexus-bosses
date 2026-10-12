-- Everything runs in data-final-fixes: the copies of enemy prototypes must see what razi-protocol (an optional
-- dependency, so it loads before) and the others have done to the originals.

local cfg = require("lib.nb_data")

for _, required in ipairs(cfg.REQUIRED) do
  local group = data.raw[required[1]]
  if not (group and group[required[2]]) then
    error("nexus-bosses: the " .. required[1] .. " " .. required[2] .. " of " .. required[3] ..
      " is missing. Update " .. required[3] .. " or report it at https://github.com/GreenTech-Solutions/nexus-bosses/issues")
  end
end

require("prototypes.nb_nexus")
require("prototypes.nb_enemies")
require("prototypes.nb_items")
require("prototypes.nb_technologies")
