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
local log = { { questID = 783, title = "A Threat Within", level = 1 }, { questID = 4641, title = "Your Place In The World", level = 1 }, { questID = 840, title = "Conscript of the Horde", level = 10 },
  { questID = 817, title = "Practical Prey", level = 8 }, { questID = 790, title = "Sarkoth", level = 4 }, { questID = 5441, title = "Lazy Peons", level = 4 } }
local objectives = { [840] = { {} }, [817] = { { text = "Durotar Tiger Fur: 2/4", finished = false } },
  [790] = { { text = "Sarkoth's Mangled Claw: 1/1", finished = os.getenv("SARKOTH_DONE") == "1" } }, [5441] = { { text = "Peons Awoken: 1/5", finished = false } } }
C_QuestLog = {
  GetNumQuestLogEntries = function() return #log end, GetInfo = function(i) return log[i] end,
  IsComplete = function(q) return q == 783 end, IsFailed = function() return false end,
  GetQuestObjectives = function(q) return objectives[q] or {} end,
}
SlashCmdList = {}
debugprofilestop = function() return os.clock() * 1000 end
NaowhForever = {}
dofile(os.getenv("NAOWH") .. "/Data/RecipeData.lua")
LW_RANK = tonumber(os.getenv("LW") or 120)
local S = { Shell = function() print("SKIN Shell") end, Font = function() end, GetAccentColor = function() return 0.05, 0.82, 0.62 end, OnLooksChanged = function() end }
EllesmereUI = { RegisterSkin = function(n, f) print("SKIN register", n) f(S) end }
if os.getenv("PRESET_CHAR") then WhatsHereCharDB = loadstring("return " .. os.getenv("PRESET_CHAR"))() end
if os.getenv("PRESET_DB") then WhatsHereDB = loadstring("return " .. os.getenv("PRESET_DB"))() end -- PRESET_DB
local chunk = assert(loadfile(arg[3]))
chunk("WhatsHere", {})
local ev = frames[1]
ev.scripts.OnEvent(ev, "ADDON_LOADED", "WhatsHere")
ev.scripts.OnEvent(ev, "PLAYER_LOGIN")
print("after login: frame shown =", WhatsHereFrame.shown, "db.shown =", WhatsHereDB.shown)
for _, f in ipairs(timers) do f() end timers = {}
local t0 = os.clock()
for _, f in ipairs(frames) do while f.scripts.OnUpdate and f.kind == "frame" do f.scripts.OnUpdate(f, 0.016) end end
print(("index built in %.1fs"):format(os.clock() - t0))
SlashCmdList.WHATSHERE("status")
WhatsHereFrame:Show()
-- print visible rows: row fontstrings are created in groups of 5 per row (line1, line2, right, header)
local rows = {}
for _, f in ipairs(frames) do if f.kind == "frame" and rawget(f, "entry") then rows[#rows+1] = f end end
for _, r in ipairs(rows) do
  local e = r.entry
  if e.header then print(("== %s (%s)"):format(e.text, tostring(e.count)))
  else print(("  %s | %s | %s | loc=%s"):format(e.kind, e.title or e.name, e.who or e.sub or e.what and (tostring(e.progress) .. " / " .. e.what) or "", e.loc and (e.loc.ui .. " " .. e.loc.x .. "," .. e.loc.y .. (e.loc.here and " here" or "")) or "nil")) end
end
rows[2].scripts.OnClick(rows[2])
for _, r in ipairs(rows) do local e = r.entry if e.kind == "vendor" then for _, x in ipairs(e.recipes) do print("    recipe", x.id, x.name) end end end
for _, r in ipairs(rows) do local e = r.entry if e.kind == "trainer" then local o = e.offer
  print("    trainer", e.name, o and ("rank=" .. tostring(o.rank and o.rank.name) .. " recipes=" .. #o.recipes .. " cost=" .. o.cost) or "no data") end end
-- fold / unfold through the title bar click
local bar for _, f in ipairs(frames) do if rawget(f, "scripts").OnMouseUp and rawget(f, "scripts").OnDragStart then bar = f end end
bar.scripts.OnMouseUp(bar, "LeftButton") print("folded:", WhatsHereDB.windowCollapsed, "sub:", WhatsHereFrame.sub.text)
bar.scripts.OnMouseUp(bar, "LeftButton") print("unfolded:", WhatsHereDB.windowCollapsed)
print("expanded sub:", WhatsHereFrame.sub.text, "icon shown:", WhatsHereFrame.questIcon.shown)
bar.scripts.OnMouseUp(bar, "LeftButton") print("folded sub:", WhatsHereFrame.sub.text)
-- right-click save toggle on the first goal row
for _, r in ipairs(rows) do local e = r.entry if e and e.kind == "goal" then r.IsMouseOver = function() return false end r.scripts.OnClick(r, "RightButton") print("saved after right-click:", WhatsHereCharDB.saved[e.quest]) break end end
