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

Console command `/nexus-bosses-abort` (administrators) stops a stuck trial.

## Remote API

Remote interface `nexus-bosses` (`scripts/nb_interface.lua`). Other mods may rely on the three functions below; the rest
of the interface (`set_ignore_player_presence`, `abort_summon`, `find_log`, `find_lair`, `repair_pylon` and the others)
is for tests and debugging, changes the game and may change in any version.

| Call | Since | Returns | Side effects |
| --- | --- | --- | --- |
| `api_version()` | 2.5.0 | `1` | none |
| `get_state()` | 2.0.0 | a table; its field `defeated` is the public part | none: it only reads |
| `open_codex(player_index, boss_id?)` | 2.2.0 | nothing | GUI of that player only, see below |

`get_state().defeated` is `{ [force_name] = { [boss_id] = boolean } }`: the victories of every force over every boss.

- A force that has never beaten a boss may have no entry: read it as nine `false`.
- An entry holds all nine boss ids, each `true` or `false`.
- When two forces merge, the victories of the source force go to the destination and the entry of the source is gone.
- The victories belong to the force, so every player of a force sees the same; the result is the same on every peer.
- The call builds the whole state: call it when a view opens or every few seconds, not every tick.

The other fields of `get_state()` (`summon`, `expedition`, `bearing`, `storms`, `story`, `vault`,
`ignore_player_presence`, `storm_weakened`) are for debugging and may change in any version.

`open_codex(player_index, boss_id?)` opens the Codex of the signal for one player on the page of a boss: `boss_id` is
one of the nine ids, `"expedition"` for the page of the expedition, or nil for the first boss. It changes no game state,
but it is not read-only: it recreates the Codex window of that player and makes it `player.opened`, so the window the
player had opened before gets `on_gui_closed`. Call it on a click of the player, not from a tick. A player that does not
exist or an unknown `boss_id` raises an error before any window changes.

Boss ids, in the order of the circles: `arachnid-queen`, `watcher`, `rogue-spidertron` (Whisper); `twin-maws`,
`colossus`, `plague-hulk` (Chorus); `storm-guardian`, `devourer`, `last-commander` (Convergence). Their names are the
locale keys `nexus-bosses.boss-<id>`. The stage technologies are `nexus-whisper`, `nexus-chorus`, `nexus-convergence`
and `nexus-silence`; `nexus-signal-bearing` researches the bearings.

Compatibility. Until the next major version of the mod:

- the names, arguments and meaning of the public part stay as they are: the three functions, `defeated`, the boss ids,
  their locale keys and the technology names above;
- new fields of `get_state()`, new optional arguments and new functions may come in any version: read only what you
  need and ignore the rest;
- a change that breaks the public part comes only with a major version and a new `api_version()`.

Check that the interface and the function exist before the call (`remote.interfaces["nexus-bosses"]`), and wrap the call
in `pcall` if your mod must not stop when the other one changes. Before 2.5.0 there is no `api_version`: read its absence
as version 1.

```lua
local api = remote.interfaces["nexus-bosses"]
if api and api.get_state then
  local ok, state = pcall(remote.call, "nexus-bosses", "get_state")
  local victories = ok and type(state) == "table" and state.defeated and state.defeated[force.name] or {}
  if victories["arachnid-queen"] then
    -- the Arachnid Queen is dead for this force
  end
end
```

## Credits

MFerrari for Big Monsters and the enemy mods the bosses come from; Karu_Kiruna for Nexus.

## License

GPLv3: [LICENSE](LICENSE).
