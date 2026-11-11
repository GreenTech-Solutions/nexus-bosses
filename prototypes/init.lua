-- The prototypes of nexus-bosses. They must see what Nexus, razi-protocol (optional) and the others have done in their
-- own data-final-fixes: the copies of enemy prototypes, the nests of Nexus and the routes of the warp drive. When
-- razi-protocol is there it runs this file as the last step of its data-final-fixes, otherwise data-final-fixes.lua does.

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
require("prototypes.nb_media")
require("prototypes.nb_expedition")
require("prototypes.nb_bearing")
require("prototypes.nb_vault")
