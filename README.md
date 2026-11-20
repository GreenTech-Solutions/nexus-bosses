# Nexus Bosses

Nine bosses on Nexus, the last planet of [Nexus Extended Promethium Endgame](https://mods.factorio.com/mod/Nexus),
for Factorio 2.1. Light a summon beacon, defend it through the precursor waves, defeat the boss and claim its trophy.
The three stages are Whisper, Chorus and Convergence. Expedition logs reveal each boss's mechanic and damage weaknesses;
precursors guard unfound wrecks and found lairs, and a lair fight increases the main mechanic's frequency. A repaired pylon
can weaken that mechanic. After all nine bosses are defeated, exploration and fights reveal the glyphs for the builders'
vault. With the warp-drive gate enabled,
the nine trophies craft a key that is consumed in the reliquary to research Silence. The mod portal page ([Nexus Bosses](https://mods.factorio.com/mod/nexus-bosses)) is
`tools/portal/description.md`. Bug reports: the issues of this repository.

Requires Nexus 1.3.6 or newer (with Nexus-Threat and Nexus-Graphics), Big Monsters, Toxic Biters, Arachnids
enemy, Electric flying enemies and TFMG: Music (the music of Nexus and the vault); razi-protocol is optional.

## Code

| Where | What |
| --- | --- |
| `lib/nb_data.lua` | the stages, the bosses, costs and health, the prototypes of other mods the mod needs |
| `prototypes/` | boss copies, beacons, trophies and the warp key, technologies, Nexus without ordinary enemies |
| `scripts/nb_summon.lua` | one summon from beacon to victory: countdown, precursors, spawn, health bar, trophy |
| `scripts/bosses/<boss>.lua` | the nine bosses the mod spawns itself and their mechanics |
| `scripts/nb_resist.lua` | weak and strong damage types computed from entity prototypes |
| `scripts/nb_telegraph.lua`, `nb_strike.lua` | ground warnings and queued strikes |
| `scripts/nb_spider.lua` | movement and targeting for spider-vehicle bosses |
| `scripts/nb_guards.lua` | precursor guards for wrecks and lairs |
| `scripts/nb_migrate.lua` | migration of saves from earlier mod data |
| `scripts/nb_bm.lua` | Big Monsters' random-event setting, Nexus exclusion and removal of monsters from disallowed surfaces |
| `scripts/nb_spawn.lua`, `nb_records.lua` | placing bosses and precursors, their orders; the entities of the active summon |
| `scripts/nb_progress.lua` | defeated bosses per force, stage research, trophies, the end of the story |
| `scripts/nb_gui.lua`, `nb_codex.lua` | the health bar; the Codex of the signal |
| `scripts/nb_expedition.lua`, `nb_story.lua` | wrecks with logs and the signal detector; the camp and the last stand |
| `scripts/nb_bearing.lua` | direction finders, lairs, pylons of suppression |
| `scripts/nb_storms.lua` | storms of Nexus-Threat wake the ruins that drop charged shards |
| `scripts/nb_vault.lua` | the vault of the builders and its glyph lock |
| `scripts/nb_whisper.lua` | hallucinations |
| `scripts/nb_nexus.lua` | the enemies of Nexus and Big Monsters' list of surfaces |
| `scripts/nb_state.lua`, `nb_interface.lua`, `nb_util.lua` | `storage`, the remote interface, shared helpers |

Console command `/nexus-bosses-abort` (administrators) stops a stuck trial.

## Remote API

Remote interface `nexus-bosses` (`scripts/nb_interface.lua`). Other mods may rely on the three functions below. The other
functions are for tests and debugging and may change in any version: `set_ignore_player_presence`, `set_countdown`,
`abort_summon`, `migrate`, `forget_migration`, `get_pending_data`, `set_tracked_health`, `set_next_colossus`, `find_log`,
`resist`, `toggle_detector`, `find_lair`, `set_finder`, `wake_ruin`, `find_story`, `defeat`, `close_reliquary`,
`repair_pylon` and `hallucinate`.

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

The other fields of `get_state()` (`summon`, `expedition`, `bearing`, `guards`, `storms`, `story`, `vault`,
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

## Tests

The FactorioTest runner is in the Factorio mod pack. From the pack directory, point it at this mod with `-m`:

```sh
tools/test/run.sh -m /path/to/nexus-bosses
```

## Credits

MFerrari for Big Monsters and the enemy mods the bosses come from; Karu_Kiruna for Nexus.

## License

GPLv3: [LICENSE](LICENSE).
