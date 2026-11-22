# What's Here

A small list window for **WoW: Forever** that answers "what can I do around here?":

- **Turn in**: every quest in your log that is ready to hand in, in any zone, with the NPC (or object) and zone. Quests you can turn in in the zone you are standing in are listed first and flagged with a pulsing **?** in the title bar, even when the window is folded.
- **Quest goals**: for quests still in progress, the nearest place in your zone to do them (the mob to kill, the object to use, the creature that drops the item, the spot to explore), with your progress.
- **Saved**: right-click any quest row to save it. Saved quests stay at the top in every zone and point to their nearest goal, or to the turn-in NPC once the quest is done. They are saved per character and drop off when you turn the quest in or abandon it.
- **Trainers**: profession trainers in your current zone, but only for professions you have and only when they can teach you something right now (a new rank or recipes).
- **Recipes**: vendors in your current zone that sell a recipe you don't know yet and have the skill for.

Click a row to set a waypoint to that NPC (the built-in map pin, or TomTom as a fallback). Hover for details.

## Install

1. Unzip so that the `WhatsHere` folder ends up in
   `World of Warcraft/_forever_/Interface/AddOns/`.
2. Make sure **QuestieDB** is installed and enabled (required).
3. Restart the game completely. A brand-new addon folder is not picked up by `/reload`.

The window opens by itself the first time.

## Dependencies

| Addon | Needed? | What it adds |
|---|---|---|
| QuestieDB | **Required** | All NPC, quest, item and zone data. |
| NaowhForever + NaowhForever_Professions | Recommended | Knows what each trainer teaches and the skill each recipe needs. Without it, trainers are shown unfiltered ("No training data") and recipes are judged only by whether the item is usable. |
| EllesmereUI + EllesmereUIBlizzardSkin | Optional | Window painted in your EUI theme. Without it, a plain dark window. |
| TomTom | Optional | Waypoint fallback where the built-in map pin can't be placed. |

## Using it

- `/wh` (or `/whatshere`) toggles the window. A key binding is under Key Bindings → AddOns → What's Here, and there is a minimap/broker button if you use a broker display or LibDBIcon.
- Drag the title bar to move the window. Click the title bar or the arrow to fold it down to just the title bar. Drag the bottom-right corner to resize it.
- The eye button changes transparency: click to step through the levels, or scroll on it for fine control.
- Click a section header to collapse it.
- Right-click a quest row to save it or remove it from Saved.
- Position, size, transparency, and the open or folded state are remembered.
- `/wh reset` puts the window back to its default place and size. `/wh status` shows whether the database index is ready and how many trainers and recipe vendors it found. `/wh perf` shows how much time the addon has used since the last `/wh perf`.

## Known limitations (test release)

- **English (enUS) client only for trainers.** Trainers are recognised by their English titles ("Alchemy Trainer", "Leathercrafter", …).
- Which recipes you already know is read from the game. Until you have opened the profession window once after logging in, a trainer may still be listed even though you know everything they teach.
- Quest progress is matched to goals by name. If the game's objective text doesn't mention the mob or item, that goal stays listed until the whole quest is complete.
- The data is only as good as QuestieDB and NaowhForever_Professions. If an NPC is missing or misplaced, please report the NPC name and zone.

## Feedback

Please report anything odd: which zone you were in, your level and professions, and what you expected to see. `/wh status` output helps.
