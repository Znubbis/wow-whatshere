-- Performance check: per-frame cost of the index build, refresh cost in a few zones, garbage per refresh.
-- Run like addontest.lua; add -joff to luajit to approximate the game's non-JIT Lua.
-- Run the addon against real QuestieDB with mocked WoW UI/API. args: questiedbDir toolsDir addonLua uiMapId
dofile(arg[2] .. "/encoding.lua")
LibQuestieDB = dofile(arg[2] .. "/harness.lua")
local MAP = tonumber(arg[4] or 1454)
bit = require("bit"); loadstring = loadstring
local timers, frames, texts = {}, {}, {}
C_Timer = { After = function(_, f) timers[#timers+1] = f end }
local function stub(kind)
  local o = { scripts = {}, shown = kind ~= "toplevel", kind = kind }
  return setmetatable(o, { __index = function(t, k)
    if k == "SetScript" then return function(self, n, f) self.scripts[n] = f end end
    if k == "GetHeight" then return function() return 440 end end
    if k == "GetFrameLevel" then return function() return 1 end end
    if k == "GetScript" then return function(self, n) return self.scripts[n] end end
    if k == "GetSize" then return function() return 380, 440 end end
    if k == "IsShown" then return function(self) return self.shown end end
    if k == "Show" then return function(self) self.shown = true if self.scripts.OnShow then self.scripts.OnShow(self) end end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if k == "SetText" then return function(self, v) self.text = v end end
    if k == "CreateFontString" then return function() local f = stub("fs") texts[#texts+1] = f return f end end
    if k == "CreateTexture" then return function() return stub("tex") end end
    if k == "CreateAnimationGroup" or k == "CreateAnimation" then return function() return stub("anim") end end
    if k == "GetPoint" then return function() return "RIGHT", nil, "RIGHT", 0, 0 end end
    if k == "RegisterEvent" then return function() end end
    return function() end
  end })
end
CreateFrame = function(_, name, parent) local f = stub(name and "toplevel" or "frame") frames[#frames+1] = f if name then _G[name] = f end return f end
UIParent = stub("ui"); UISpecialFrames = {}; GameTooltip = stub("tt"); GameTooltip_Hide = function() end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("CHAT", m) end }
geterrorhandler = function() return function(e) print("ERROR", e) end end
GetTime = function() return os.clock() end
UnitFactionGroup = function() return "Horde" end
ITEM_SPELL_KNOWN = "Already known"
GetProfessions = function() return 1, 2 end
GetProfessionInfo = function(i) if i == 1 then return "Leatherworking", 0, LW_RANK, 150, 0, 0, 165 elseif os.getenv("ALCH") then return "Alchemy", 0, tonumber(os.getenv("ALCH")), 225, 0, 0, 171 else return "Skinning", 0, 110, 150, 0, 0, 393 end end
IsPlayerSpell = function(id) return id < 5000 end
C_Spell = { GetSpellName = function(id) return "Spell" .. id end }
GetCoinTextureString = function(c) return c .. "c" end
C_Item = { IsUsableItem = function(id) if os.getenv("USABLE") then return os.getenv("USABLE") == "1" end return id % 2 == 0 end, GetItemNameByID = function() return nil end, RequestLoadItemDataByID = function() end }
CreateVector2D = function(x, y) return { GetXY = function() return x, y end } end
C_Map = {
  GetBestMapForUnit = function() return MAP end,
  GetMapInfo = function(id) return { name = "Map" .. id, mapType = 3, parentMapID = 1411 } end,
  GetPlayerMapPosition = function() return CreateVector2D(0.5, 0.5) end,
  GetWorldPosFromMapPos = function(ui, v) local x, y = v:GetXY() return 1, CreateVector2D(x * 1000, y * 1000) end,
  CanSetUserWaypointOnMap = function() return true end, SetUserWaypoint = function(p) print("WAYPOINT", p.map, p.x, p.y) end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { map = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
GetQuestDifficultyColor = function() return { r = 1, g = 1, b = 0 } end
local log = { { questID = 783, title = "A Threat Within", level = 1 }, { questID = 4641, title = "Your Place In The World", level = 1 }, { questID = 840, title = "Conscript of the Horde", level = 10 } }
C_QuestLog = {
  GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
  IsComplete = function(q) return q == 783 end, IsFailed = function() return false end,
  GetQuestObjectives = function(q) if q == 840 then return { {} } end return {} end,
}
SlashCmdList = {}
debugprofilestop = function() return os.clock() * 1000 end
NaowhForever = {}
dofile(os.getenv("NAOWH") .. "/Data/RecipeData.lua")
LW_RANK = tonumber(os.getenv("LW") or 120)
local S = { Shell = function() print("SKIN Shell") end, Font = function() end, GetAccentColor = function() return 0.05, 0.82, 0.62 end, OnLooksChanged = function() end }
EllesmereUI = { RegisterSkin = function(n, f) print("SKIN register", n) f(S) end }
if os.getenv("PRESET_DB") then WhatsHereDB = loadstring("return " .. os.getenv("PRESET_DB"))() end -- PRESET_DB
local chunk = assert(loadfile(arg[3]))
chunk("WhatsHere", {})
local ev = frames[1]
ev.scripts.OnEvent(ev, "ADDON_LOADED", "WhatsHere")
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
print("after login: frame shown =", WhatsHereFrame.shown, "db.shown =", WhatsHereDB.shown)
-- ---- perf: realistic quest log (25 quests, 12 complete) ----
local qids, n = LibQuestieDB.Quest.GetAllIds(), 0
local big = {}
for i = 1, #qids, math.floor(#qids / 25) do
  if #big >= 25 then break end
  big[#big + 1] = { questID = qids[i], title = "Q" .. qids[i], level = 20 }
end
C_QuestLog.GetNumQuestLogEntries = function() return #big end
C_QuestLog.GetInfo = function(i) return big[i] end
C_QuestLog.IsComplete = function(q) return q % 2 == 0 end
C_QuestLog.GetQuestObjectives = function() return { {} } end
local clock = os.clock
debugprofilestop = function() return clock() * 1000 end
for _, f in ipairs(timers) do f() end timers = {}
-- index build: time each OnUpdate (one game frame)
local worst, frames_n, total = 0, 0, clock()
for _, f in ipairs(frames) do
  while f.scripts.OnUpdate and f.kind == "frame" and f ~= WhatsHereFrame do
    local t = clock(); f.scripts.OnUpdate(f, 0.016); local d = (clock() - t) * 1000
    frames_n = frames_n + 1; if d > worst then worst = d end
  end
end
print(("index: %d frames, %.0f ms total, worst frame %.1f ms"):format(frames_n, (clock() - total) * 1000, worst))
collectgarbage("collect")
print(("memory after index: %.1f MB (whole Lua state incl. QuestieDB harness)"):format(collectgarbage("count") / 1024))
WhatsHereFrame:Show()
local Refresh = function() WhatsHereFrame.scripts.OnUpdate(WhatsHereFrame, 4) end
for _, map in ipairs({ 1458, 1454, 1453, 1446, 1443, 1413 }) do
  MAP = nil
  C_Map.GetBestMapForUnit = function() return map end
  local t = clock(); Refresh(); local first = (clock() - t) * 1000
  t = clock(); for i = 1, 20 do Refresh() end; local warm = (clock() - t) * 1000 / 20
  print(("map %d: first refresh %.1f ms, then %.2f ms each"):format(map, first, warm))
end
local Refresh = function() WhatsHereFrame.scripts.OnUpdate(WhatsHereFrame, 4) end
local m0 = collectgarbage("count")
for i = 1, 200 do Refresh() end
print(("garbage from 200 refreshes: %.0f KB"):format(collectgarbage("count") - m0))
SlashCmdList.WHATSHERE("perf")
