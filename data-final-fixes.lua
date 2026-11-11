-- Nexus lists nexus-bosses as an optional dependency, so nexus-bosses loads before Nexus and before razi-protocol, which
-- requires Nexus. Its prototypes must see their final enemies and technologies, so razi-protocol makes them at the end
-- of its own data-final-fixes and says so with the mod-data "nexus-bosses-late". Without it they are made here, before
-- the data-final-fixes of Nexus: with Krastorio 2 Spaced Out, Nexus redefines the warp drive there and the trials gate
-- none of its routes.
local late = data.raw["mod-data"] and data.raw["mod-data"]["nexus-bosses-late"]
if late then
  log("[nexus-bosses] the prototypes are made at the end of the data-final-fixes of " .. tostring(late.data.mod))
  return
end
require("prototypes.init")
