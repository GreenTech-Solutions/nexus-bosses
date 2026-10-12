-- Sounds, music and effect sprites. Authors and licenses: CREDITS.md.
--   sound          nexus-bosses-<name>, played to a force by scripts/nb_util.lua (force.play_sound)
--   ambient-sound  nexus-bosses-fight-*: script tracks, the music of a fight (force.play_music);
--                  nexus-bosses-signal: the Nexus music of TFMG-music, only with that mod (its author asks for it to be
--                  used as a dependency)
--   animation      nexus-bosses-summon-circle under a lit beacon; sprite nexus-bosses-spark on a feeding Storm Guardian;
--                  sprite nexus-bosses-vignette: the edges of the screen darken in a hallucination (scripts/nb_whisper.lua)

local cfg = require("lib.nb_data")

local SOUNDS = "__nexus-bosses__/sounds/"

-- name, volume, category
local EFFECTS = {
  { "call", 0.9, "alert" },
  { "countdown", 0.7, "alert" },
  { "precursors", 0.8, "enemy" },
  { "queen-nests", 0.8, "enemy" },
  { "hulk-spores", 0.7, "enemy" },
  { "guardian-feeds", 0.6, "enemy" },
  { "devourer-burrow", 1.0, "enemy" },
  { "victory", 0.8, "gui-effect" },
  { "stage-complete", 0.8, "gui-effect" },
  { "trophy", 0.7, "gui-effect" },
  { "silence", 0.9, "gui-effect" },
  { "arrive-storm-guardian-stinger", 0.8, "enemy" },
}
for _, id in ipairs(cfg.ORDER) do
  EFFECTS[#EFFECTS + 1] = { "arrive-" .. id, 0.9, "enemy" }
end

local prototypes = {}
for _, effect in ipairs(EFFECTS) do
  prototypes[#prototypes + 1] = {
    type = "sound",
    name = "nexus-bosses-" .. effect[1],
    filename = SOUNDS .. effect[1] .. ".ogg",
    volume = effect[2],
    category = effect[3],
  }
end

for _, track in ipairs({ "fight-urgent", "fight-pulse" }) do
  prototypes[#prototypes + 1] = {
    type = "ambient-sound",
    name = "nexus-bosses-" .. track,
    track_type = "script-track",
    sound = { filename = "__nexus-bosses__/music/" .. track .. ".ogg", volume = 0.6 },
  }
end

if mods["TFMG-music"] then
  prototypes[#prototypes + 1] = {
    type = "ambient-sound",
    name = "nexus-bosses-signal",
    track_type = "main-track",
    planets = { cfg.PLANET },
    sound = { filename = "__TFMG-music__/space/FIELDS.ogg", volume = 0.5 },
  }
end

prototypes[#prototypes + 1] = {
  type = "animation",
  name = "nexus-bosses-summon-circle",
  filename = "__nexus-bosses__/graphics/effects/summon-circle.png",
  width = 128,
  height = 128,
  line_length = 4,
  frame_count = 16,
  animation_speed = 0.25,
  scale = 1.2,
  blend_mode = "additive",
}
prototypes[#prototypes + 1] = {
  type = "sprite",
  name = "nexus-bosses-vignette",
  filename = "__nexus-bosses__/graphics/effects/vignette.png",
  size = 512,
  flags = { "no-crop" },
}
prototypes[#prototypes + 1] = {
  type = "sprite",
  name = "nexus-bosses-spark",
  filename = "__nexus-bosses__/graphics/effects/spark.png",
  size = 128,
  blend_mode = "additive",
}

data:extend(prototypes)
