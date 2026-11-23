**Summary** (CurseForge "Summary" field):

Quests to turn in, where to do the rest, and the trainers and recipe vendors worth visiting in your zone. Click any row for a waypoint.

---

**Description** (CurseForge "Description" field, Markdown):

# What's Here

**A small list window for WoW: Forever that answers "what can I do around here?"**

What's Here goes through your quest log, your professions and the zone you're standing in. It shows only what you can act on right now. Click any row and it sets a waypoint.

## What it shows

- **Turn in.** Every quest in your log that is ready to hand in, in any zone, with the NPC and zone. Quests you can turn in where you're standing come first. A pulsing **?** in the title bar flags them, even when the window is folded.
- **Quest goals in your zone.** For each quest still in progress, the nearest place to work on it, with your progress (e.g. *Durotar Tiger Fur: 2/4*). That can be a mob to kill, an object to use, a creature that drops the item, or a spot to explore.
- **Saved quests.** Right-click a quest to save it. Saved quests stay at the top in every zone and point to the next goal, or to the turn-in NPC once the quest is done. They are kept per character and drop off when you turn the quest in.
- **Trainers.** Profession trainers in your zone. It only lists trainers for professions you have, and only when they can teach you something now: a new rank, or recipes you have the skill for.
- **Recipes.** Vendors in your zone that sell a recipe you don't know yet and can learn at your current skill.

## Using it

- `/wh` toggles the window. There is also a key binding and a minimap button.
- Click a row to set a waypoint (built-in map pin, or TomTom as a fallback). Hover a row for details: objectives, what a trainer teaches and what it costs, recipe prices.
- Drag the title bar to move the window. Click the title bar to fold the window down to a one-line summary. Drag the corner to resize it.
- The eye button sets the transparency.
- The window remembers its position, size and open or folded state.
- If you use **EllesmereUI**, the window follows your EUI theme.

## Requirements

- **QuestieDB** (required): all the quest, NPC and item data comes from it.
- **NaowhForever + NaowhForever Professions** (recommended): lets the addon tell exactly what a trainer can teach you and the skill each recipe needs. Without it, trainers are shown unfiltered.
- EllesmereUI and TomTom are optional.

## Lightweight

There is no combat-log or OnUpdate scanning. The list refreshes a few times a minute while the window is open, and each refresh takes about a millisecond. `/wh perf` shows exactly how much time it uses.

## Known limitations

- Trainers are recognised by their English titles, so trainer filtering needs an English (enUS) client.
- Quest progress is matched to goals by name. A goal whose objective text doesn't name the mob or item stays listed until the quest is complete.

Bug reports and ideas are welcome: [github.com/Znubbis/wow-whatshere](https://github.com/Znubbis/wow-whatshere/issues). Please include your zone and the output of `/wh status`.
