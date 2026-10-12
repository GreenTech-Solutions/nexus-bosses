# Nexus Bosses

Nine bosses on Nexus, the last planet of [Nexus Extended Promethium Endgame](https://mods.factorio.com/mod/Nexus-Updated),
for Factorio 2.1. You call them yourself: light a summon beacon on Nexus, hold it through the countdown and its precursor
waves, kill the boss and take its trophy. The signal grows over three stages (Whisper, Chorus, Convergence); the nine trophies make
the warp key, which researches Silence and opens the routes of the warp drive. The mod portal page ([Nexus Bosses](https://mods.factorio.com/mod/nexus-bosses)) is
`tools/portal/description.md`. Bug reports: the issues of this repository.

Requires Nexus-Updated (with Nexus-Threat-Updated and Nexus-Graphics-Updated), Big Monsters, Toxic Biters, Arachnids
enemy, Electric flying enemies and TFMG: Music (the music of Nexus); razi-protocol is optional.

## Code

| Where | What |
| --- | --- |
| `lib/nb_data.lua` | the stages, the bosses, costs and health, the prototypes of other mods the mod needs |
| `prototypes/` | boss copies, beacons, trophies and the warp key, technologies, Nexus without ordinary enemies |
| `scripts/nb_summon.lua` | one summon from beacon to victory: countdown, precursors, spawn, health bar, trophy |
| `scripts/bosses/<boss>.lua` | the bosses the mod spawns itself and their mechanics |
| `scripts/nb_bm.lua` | the bosses of Big Monsters: the event, moving the boss to the beacon, the map setting |

Remote interface `nexus-bosses`: `get_state()`, `set_ignore_player_presence(bool)` (headless tests),
`abort_summon(destroy_bosses)`. Console command `/nexus-bosses-abort` (administrators) stops a stuck trial.

## Credits

MFerrari for Big Monsters and the enemy mods the bosses come from; Karu_Kiruna for Nexus.

## License

GPLv3: [LICENSE](LICENSE).
