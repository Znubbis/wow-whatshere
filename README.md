# What's Here

A WoW: Forever addon that lists quests you can turn in (all zones), where to do your unfinished quests in the current zone, and profession trainers and recipe vendors worth visiting there. Right-click a quest to keep it on top in every zone; click any row to set a waypoint.

![What's Here in Desolace: one quest to turn in elsewhere, four recipe vendors nearby](docs/screenshot.png)

**Download:** grab `WhatsHere-x.y.z.zip` from [Releases](../../releases), unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, and restart the game. Requires **QuestieDB**.

Full description, dependencies and known limitations: [WhatsHere/README.md](WhatsHere/README.md).

## Repository layout

- `WhatsHere/`: the addon itself (this folder is what goes into `AddOns/`).
- `tools/`: offline test harness for luajit. It loads the real QuestieDB data outside the game and runs the addon against a mocked WoW UI:

  ```
  cd tools
  NAOWH=<path to NaowhForever_Professions> luajit addontest.lua <path to QuestieDB> "$PWD" ../WhatsHere/WhatsHere.lua <uiMapId>
  ```

  `encoding.lua` emulates `C_EncodingUtil` (base64, zlib via the luajit FFI, CBOR), so libz must be installed.
- `curseforge/`: logo and page text for the CurseForge project (id 1826342).
- `.github/workflows/release.yml`: pushing a `v*` tag packages `WhatsHere/` with the BigWigs packager and uploads it to CurseForge and GitHub Releases. Bump `## Version` in the TOC first. The CurseForge API token is the repository secret `CF_API_TOKEN`.
