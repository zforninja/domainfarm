# FFXI Domain Invasion Auto-Farmer (DomainFarm)
**Author:** Zforninja  
**Version:** 8.2  
**Platform:** Final Fantasy XI (Windower 4)

A fully automated, state-machine-driven Lua script for Windower 4 that continuously farms Domain Invasion (Escha Beads) across all three zones: **Reisenjima**, **Escha - Zi'Tah**, and **Escha - Ru'Aun**. 

Unlike basic scripts that sit in one zone and wait, this script utilizes a 10-phase self-healing state machine to actively rotate through the zones, acquire Elvorseals, summon Trusts, flank the dragons to avoid breath attacks, and safely warp out—all while auto-correcting itself if a ring is on cooldown or a manual zone change occurs.

---

## 🌟 Key Features

* **Full 3-Zone Rotation:** Automatically cycles through Quetzalcoatl, Azi Dahaka, and Naga Raja sequentially.
* **Self-Healing State Machine:** If you manually warp to a town, or if your ring is on cooldown, the script automatically detects your new zone and resumes the correct phase without breaking.
* **Superwarp Integration:** Uses `//sw` commands to instantly grab Elvorseals (`//sw ew domain`) and seamlessly travel between Home Points and Escha Confluxes.
* **Smart Combat Positioning:** Automatically paths to the *flank* of the dragons in Zi'Tah and Ru'Aun to protect your Trusts from frontal breath cleaves.
* **Phantom Spawn Detection:** Bypasses FFXI's invisible "dummy" spawns (`valid_target` check) to ensure your character only engages when the real dragon is targetable.
* **Auto-Trust Summoning:** Dynamically summons a pre-configured list of Trusts before every fight.

---

## 📋 Prerequisites

To use this script, you must have the following configured in your Windower 4 setup:

1. **Superwarp Addon:** Must be installed and functioning to handle fast travel and Elvorseal acquisition.
2. **Teleportation Rings:** 
   * `Dim. Ring (Dem)` (or configured equivalent for Reisenjima access).
   * `Warp Ring` (for returning to a safe zone/Home Point after a kill).
3. **Unlocked Waypoints:**
   * Qufim Island Home Point #1 (For Escha - Zi'Tah).
   * Misareaux Coast Home Point #1 (For Escha - Ru'Aun).
   * The Dimensional Portal at the Crag of Dem.

---

## 🚀 Installation & Configuration

1. Download `domainfarm.lua` and place it in your Windower `addons/domainfarm/` folder (create the folder if it doesn't exist).
2. Open `domainfarm.lua` in a text editor to configure your specific loadout:

**Set Your Rings:**
```lua
local teleport_ring = "Dim. Ring (Dem)"
local warp_ring = "Warp Ring"
Set Your Trusts:Customize the trust_list table with your preferred Trust magic names. You can provide an alternative (alt) in case a specific Trust is unavailable:Lualocal trust_list = {
    {spell = 'Ulmia', alt = 'Arciella II'},
    {spell = 'Qultada', alt = ''},
    {spell = 'Koru-Moru', alt = ''},
    {spell = 'Joachim', alt = 'Lilisette'},
    {spell = 'Sylvie (UC)', alt = 'Prishe II'}
}
```
## 🎮 Commands

All commands are executed using `//domainfarm`.

| Command | Description |
| :--- | :--- |
| `//domainfarm start` | Starts the script natively at **Reisenjima** (Quetzalcoatl). Uses the Teleport Ring to begin the loop. |
| `//domainfarm start zitah` | Jumpstarts the script for **Escha - Zi'Tah** (Azi Dahaka). Uses the Warp Ring to transit to Qufim. |
| `//domainfarm start ruaun` | Jumpstarts the script for **Escha - Ru'Aun** (Naga Raja). Uses the Warp Ring to transit to Misareaux. |
| `//domainfarm stop` | Halts the script, clears the active phase, and stops character movement instantly. |
| `//domainfarm mark` | Developer tool: Prints your current X/Y coordinates to the chat log for building custom waypoint paths. |

---

## 🛠️ How It Works (The 10-Phase Loop)

1. **Phase 1:** Equips and casts the Teleport Ring.
2. **Phase 2:** Runs to the Dimensional Portal and injects menu packets to enter Reisenjima.
3. **Phase 3:** Walks custom waypoint paths from the Escha Conflux to the local Elvorseal NPC.
4. **Phase 4:** Fires `//sw ew domain` to request the Elvorseal.
5. **Phase 5:** Verifies Elvorseal application (Buff ID 603). Locks out for 60 seconds and retries if rejected.
6. **Phase 6:** Runs to the arena flank, summons Trusts, waits for the real spawn, engages, and fights until dead.
7. **Phase 7:** Equips and casts the Warp Ring.
8. **Phase 8:** Acknowledges arrival at a safe zone and uses `//sw` to jump to Qufim or Misareaux.
9. **Phase 9:** Walks the tunnel waypoints to the Undulating Conflux.
10. **Phase 10:** Enters the Escha zone via Superwarp. 

*(If a ring is down, manually cast Warp or use a Home Point. The self-healing logic will instantly recognize the new zone and advance the bot to the correct phase).*

---

## ⚠️ Disclaimer
This script automates gameplay mechanics in Final Fantasy XI. Use at your own risk. The author is not responsible for any account actions, bans, or penalties incurred from the use of this software. Please respect the server and other players.
