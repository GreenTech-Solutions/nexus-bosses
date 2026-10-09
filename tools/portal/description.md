Nine bosses in three circles on Nexus, the planet of [Nexus Extended Promethium Endgame](https://mods.factorio.com/mod/Nexus-Updated). You call them yourself: craft a summon beacon, place it on Nexus, defend it through the countdown and defeat the boss that comes. Source and bug reports: [GreenTech-Solutions/nexus-bosses](https://github.com/GreenTech-Solutions/nexus-bosses).

## How it works

- **Circle I** opens when you build a shield stabilizer on Nexus. Its three beacons cost omega alloy and advanced photon processors and are crafted on Nexus.
- A lit beacon counts down (60 s by default) while a player of your force is on Nexus. Then the boss comes. Picking up or losing the beacon during the countdown cancels the summon. The beacon is immune to lightning.
- Every beacon tells the health and the resistances of its boss, so you can prepare.
- Beating the three bosses of a circle opens the next one. Beating circle III completes the trials and opens the warp drive (the way to the Oort cloud and Sol).
- When the Storm Guardian falls, the lightning of the storms of Nexus is permanently weaker.

## The bosses

| Circle | Boss | Comes | Victory |
| --- | --- | --- | --- |
| I | Arachnid Queen (500,000) + four leviathans | on foot, 150-250 tiles away | the queen is dead |
| I | Flying Saucer (Big Monsters) | several hundred tiles away | every new saucer is destroyed |
| I | Evil Spider (Big Monsters) | several hundred tiles away | every new spidertron is destroyed |
| II | Great Worms (Big Monsters) | burrow up inside your base | every new boss worm is dead |
| II | Biterzilla (Big Monsters) | several hundred tiles away | every new boss is dead |
| II | Toxic Lair (2,000,000), a crashed ship with boss biters and turrets | lands 150-250 tiles away | the ship is destroyed |
| III | Storm Guardian (1,000,000) + 20 walkers and 20 flyers | 150-250 tiles away | the guardian is dead |
| III | Host Worm (5,000,000), a giant demolisher | crawls in from 150-250 tiles away | the worm is dead |
| III | Final Boss (Big Monsters) | several hundred tiles away | every new ultimate boss is dead |

Health is shown at the default settings.

## Settings

- **Startup:** boss health multiplier, summon beacon cost multiplier, whether the trials gate the warp drive.
- **Map:** countdown length, whether Big Monsters is kept off the other planets.

## Good to know

- **Nexus has no ordinary nests or worms:** its enemies come only from the beacons. Enemy evolution on Nexus is fixed at 0.99, so the bosses come in their strongest variants.
- **Big Monsters:** the chances of its random events start at 0 with this mod. Raise them in the map settings of Big Monsters if you want them elsewhere.
- **Without razi-protocol** the warp drive of Nexus also leads to the shattered planet and promethium, so the trials gate those too. Turn the startup setting off if you do not want that.
- **One trial at a time** on the whole server, for every force.
- **Added to a running game:** the enemies already on Nexus are removed. If a shield stabilizer stands there, circle I opens.
- Administrators can stop a stuck trial with `/nexus-bosses-abort`. Other mods can use the remote interface `nexus-bosses` (`get_state`, `abort_summon`).

## Requirements

Nexus-Updated (with Nexus-Threat-Updated and Nexus-Graphics-Updated), Big Monsters, Toxic Biters, Arachnids enemy and Electric flying enemies. razi-protocol is optional.

## Credits

- MFerrari for Big Monsters and the enemy mods the bosses come from
- Karu_Kiruna for Nexus
