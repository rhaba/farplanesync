# farplanesync (Ashita v4, PhoenixXI)

<!-- staff-approval -->
## Approval by staff

| Version | Status | Submitted | Reviewed by | Notes |
|---|---|---|---|---|
| 0.1.0 | Pending review | 2026-10-16 |  | Read only, sends nothing to the game server. Writes your own character's progress to a local file. |

**Author:** Spongeh. **Program:** Ashita v4. **Type:** read only, no display, no automation. It reads your own character's job levels, nation rank, key items, and quest and mission logs, all of which the client already has, and writes them to a JSON file on your PC. It never sends packets, never acts in game, and never goes online. A separate uploader script, run outside the game, sends that file to the Farplane linkshell site.
<!-- /staff-approval -->

---

Keeps your progress on the **Farplane linkshell portal** ([farplane.org/portal](https://farplane.org/portal)) up to date, so you don't have to tick milestones by hand. When you finish a mission, get a key item, or level a job, the portal updates on its own.

## Install

1. Copy the `farplanesync` folder into `Ashita\addons\`.
2. In game, run `/addon load farplanesync`. To load it every time, add that line to your Ashita script.
3. On the portal, go to **My progress > In-game sync** and click **Create key**.
4. In game, run `/fps upload`, or double-click `tools\uploader.bat`. A console window opens. Paste your key the first time it asks.

Leave the uploader window open while you play, and close it to stop. Without it running, nothing leaves your PC.

## Commands

| Command | What it does |
|---|---|
| `/fps` | Shows whether the quest and mission logs have arrived, and the last file written |
| `/fps write` | Writes the file now |
| `/fps upload` | Opens the uploader window (outside the game) |

The server sends the quest and mission logs at login and when you zone. If you load the addon mid-session, zone once. The logs are saved per character, so later sessions keep them.

## What it reads

Everything below is about **your own character**, and the client already has all of it:

| Data | Where it comes from |
|---|---|
| Job levels, main/sub job, nation, nation rank | Ashita's player memory (`GetJobLevel`, `GetMainJob`, `GetNation`, `GetRank`, …) |
| Key items you hold | Ashita's player memory (`HasKeyItem`) |
| Current and completed quests | Incoming packet `0x056`, quest log ports `0x50`–`0xC0`. The server sends this to every client to fill in the quest log. |
| Current and completed missions (nation, Zilart, Promathia, Aht Urhgan) | Incoming packet `0x056`, ports `0xFFFF`, `0x80`, `0xD0` and `0xD8` |

Packet layouts follow LandSandBoat / PhoenixXI `src/map/packets/s2c/0x056_mission*.cpp`.

## What it does NOT do

- It never sends or injects packets, and never modifies or blocks incoming ones. It only reads `0x056`.
- It takes no action in game: no movement, targeting, commands or automation.
- It reads nothing about other players.
- It makes no network connections. The addon only writes files in its own folder.
- It doesn't read your inventory, gil, position or chat.

## What it writes

`out\<CharacterName>.json`, rewritten when something changes. It looks roughly like this:

```json
{
  "name": "Shantotto", "main_job": "BLM", "main_level": 75, "sub_job": "WHM", "sub_level": 37,
  "nation": "Windurst", "rank": 10,
  "jobs": { "BLM": 75, "WHM": 37 },
  "key_items": [8, 138, 492],
  "quests": { "current": { "3": [130] }, "completed": { "3": [128, 129] } },
  "missions": { "nation": 2, "nation_current": 23, "zilart_current": 26, "cop_current": 358,
                "toau_current": 4, "zilart_completed": [0, 4, 6], "toau_completed": [0, 1, 2, 3] },
  "addon": "farplanesync", "version": "0.1.0", "written_at": 1790000000
}
```

Open it in a text editor any time to see exactly what gets uploaded.

## The uploader (`tools\uploader.ps1`)

A short PowerShell script that runs outside the game:

- It checks `out\` every 20 seconds. When a file's content has changed, it POSTs that file to `https://farplane.org/api/game/report` with your key. That is the only address it contacts.
- Your key is saved in `tools\.key` on your PC. A key can only update characters linked to your own Discord account on the portal. Revoke it on the portal any time.
- The portal only stores the progress fields above. It uses them to fill in your jobs and missions and to tick milestones its leaders have mapped, for example holding the Chocobo license key item ticks "Chocobo license".

## Files

| File | Purpose |
|---|---|
| `farplanesync.lua` | The addon |
| `fps/json.lua` | A small JSON writer |
| `tools/uploader.ps1`, `tools/uploader.bat` | The uploader (outside the game) |

## License

MIT
