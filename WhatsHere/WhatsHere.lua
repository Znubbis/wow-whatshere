-- What's Here: quests you can turn in (all zones), profession trainers and recipe vendors
-- in the current zone, with a click-to-waypoint list. Data comes from QuestieDB.

local ADDON = ...
local LQ = _G.LibQuestieDB
local band = bit.band
local huge = math.huge

local TRAINER_FLAG = 16 -- QuestieDB npcFlags.TRAINER (Forever)
local RECIPE_CLASS = 9  -- item class "Recipe"
local MICRO_MAP = (Enum and Enum.UIMapType and Enum.UIMapType.Micro) or 5
local ROW_H = 32
local PAD = 10
local BAR_H = 25 -- matches the EllesmereUI shell title strip
local BOTTOM = 22

-- skillLine -> English trainer-subName stems (enUS client), recipe subclass, fallback label
local SKILLS = {
    [171] = { label = "Alchemy",        sub = 6,  stems = { "alchem" } },
    [164] = { label = "Blacksmithing",  sub = 4,  stems = { "blacksmith", "armorsmith", "weaponsmith" } },
    [333] = { label = "Enchanting",     sub = 8,  stems = { "enchant" } },
    [202] = { label = "Engineering",    sub = 3,  stems = { "engineer" } },
    [165] = { label = "Leatherworking", sub = 1,  stems = { "leatherwork", "leathercraft" } },
    [197] = { label = "Tailoring",      sub = 2,  stems = { "tailor" } },
    [755] = { label = "Jewelcrafting",  sub = 10, stems = { "jewelcraft" } },
    [185] = { label = "Cooking",        sub = 5,  stems = { "cook", "chef" } },
    [129] = { label = "First Aid",      sub = 7,  stems = { "first aid", "physician", "medic", "surgeon" } },
    [356] = { label = "Fishing",        sub = 9,  stems = { "fishing", "fisher" } },
    [182] = { label = "Herbalism",                stems = { "herbalis" } },
    [186] = { label = "Mining",                   stems = { "mining", "miner" } },
    [393] = { label = "Skinning",                 stems = { "skinn" } },
}
local SUB_TO_SKILL = {}
for line, s in pairs(SKILLS) do
    if s.sub then SUB_TO_SKILL[s.sub] = line end
end

local db
local playerFaction = "A"
local zones = { areaToUi = {}, uiToArea = {}, parent = {} }
local index = { state = "waiting", trainers = {}, vendors = {} }
local mySkills = {}
local npcCache, objCache, knownCache = {}, {}, {}
local zoneCache = {}
local rows, model, offset = {}, {}, 0
local frame
local Refresh

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99What's Here|r: " .. msg)
end

----------------------------------------------------------------------------------------------
-- Data
----------------------------------------------------------------------------------------------

local function Decode(src)
    if type(src) == "table" then return src end
    if type(src) ~= "string" then return {} end
    local chunk = loadstring(src)
    if not chunk then return {} end
    local ok, t = pcall(chunk)
    return (ok and type(t) == "table") and t or {}
end

local function LoadZones()
    local z = LQ.Support and LQ.Support.Get and LQ.Support.Get("ZoneDB")
    local p = z and z.private or {}
    local function merged(base, override)
        local t = Decode(p[base])
        for k, v in pairs(Decode(p[override])) do t[k] = v end
        return t
    end
    zones.areaToUi = merged("areaIdToUiMapId", "areaIdToUiMapIdOverride")
    zones.uiToArea = merged("uiMapIdToAreaId", "uiMapIdToAreaIdOverride")
    zones.parent = merged("subZoneToParentZone", "subZoneToParentZoneOverride")
end

local function AreaUi(area)
    local ui = zones.areaToUi[area]
    if ui and ui > 0 then return ui end
end

local function NpcInfo(id)
    local c = npcCache[id]
    if not c then
        local N = LQ.Npc
        c = {
            id = id,
            name = N.name(id) or ("NPC " .. id),
            sub = N.subName(id),
            spawns = N.spawns(id),
            zone = N.zoneID(id),
            faction = N.friendlyToFaction(id),
        }
        npcCache[id] = c
    end
    return c
end

local function ObjInfo(id)
    local c = objCache[id]
    if not c then
        local O = LQ.Object
        c = { id = id, name = O.name(id) or ("Object " .. id), spawns = O.spawns(id), zone = O.zoneID(id) }
        objCache[id] = c
    end
    return c
end

local function Friendly(info)
    return not info.faction or info.faction:find(playerFaction, 1, true) ~= nil
end

local function MatchSkill(subName)
    local s = subName:lower()
    for line, def in pairs(SKILLS) do
        for _, stem in ipairs(def.stems) do
            if s:find(stem, 1, true) then return line end
        end
    end
end

local function ScanProfessions()
    wipe(mySkills)
    if GetProfessions and GetProfessionInfo then
        for _, idx in pairs({ GetProfessions() }) do
            local name, _, rank, maxRank, _, _, line = GetProfessionInfo(idx)
            if line then mySkills[line] = { name = name, rank = rank, max = maxRank } end
        end
    end
    if not next(mySkills) and GetNumSkillLines and GetSkillLineInfo then
        for i = 1, GetNumSkillLines() do
            local name, header, _, rank, _, _, maxRank = GetSkillLineInfo(i)
            if name and not header then
                for line, def in pairs(SKILLS) do
                    if def.label == name then mySkills[line] = { name = name, rank = rank, max = maxRank } end
                end
            end
        end
    end
    wipe(zoneCache)
end

local function SkillName(line)
    return (mySkills[line] and mySkills[line].name) or (SKILLS[line] and SKILLS[line].label) or "?"
end

-- One pass over every NPC and item, spread over frames: trainer list + vendor -> recipes.
local function BuildIndex()
    index.state = "building"
    local co = coroutine.create(function()
        local N, I = LQ.Npc, LQ.Item
        local ids = N.GetAllIds()
        for i = 1, #ids do
            local id = ids[i]
            local flags = N.npcFlags(id)
            if flags and band(flags, TRAINER_FLAG) ~= 0 then
                local sub = N.subName(id)
                local line = sub and MatchSkill(sub)
                if line then index.trainers[#index.trainers + 1] = { id = id, skill = line } end
            end
            if i % 250 == 0 then coroutine.yield() end
        end
        ids = I.GetAllIds()
        for i = 1, #ids do
            local id = ids[i]
            if I.class(id) == RECIPE_CLASS then
                local line = SUB_TO_SKILL[I.subClass(id) or -1]
                local vendors = line and I.vendors(id)
                if vendors and #vendors > 0 then
                    local spell = I.teachesSpell(id)
                    local rec = { id = id, skill = line, spell = (spell and spell > 0) and spell or nil, name = I.name(id) }
                    for _, v in ipairs(vendors) do
                        local list = index.vendors[v]
                        if not list then
                            list = {}
                            index.vendors[v] = list
                        end
                        list[#list + 1] = rec
                    end
                end
            end
            if i % 250 == 0 then coroutine.yield() end
        end
    end)
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(self)
        local start = debugprofilestop()
        while debugprofilestop() - start < 6 do
            local ok, err = coroutine.resume(co)
            if not ok then
                index.state = "error"
                self:SetScript("OnUpdate", nil)
                geterrorhandler()(err)
                Refresh()
                return
            end
            if coroutine.status(co) == "dead" then
                index.state = "ready"
                self:SetScript("OnUpdate", nil)
                wipe(zoneCache)
                Refresh()
                return
            end
        end
    end)
end

----------------------------------------------------------------------------------------------
-- Positions
----------------------------------------------------------------------------------------------

local function WorldPos(ui, x, y) -- x, y in 0..1
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    local ok, inst, pos = pcall(C_Map.GetWorldPosFromMapPos, ui, CreateVector2D(x, y))
    if ok and inst and pos then
        local wx, wy = pos:GetXY()
        return inst, wx, wy
    end
end

local function ZoneName(ui)
    local info = ui and C_Map.GetMapInfo(ui)
    return info and info.name or "?"
end

local function CurrentZone()
    local ui = C_Map.GetBestMapForUnit("player")
    if not ui then return nil end
    local info = C_Map.GetMapInfo(ui)
    while info and info.mapType == MICRO_MAP and info.parentMapID and info.parentMapID > 0 do
        ui = info.parentMapID
        info = C_Map.GetMapInfo(ui)
    end
    local cur = { ui = ui, area = zones.uiToArea[ui], name = (info and info.name) or GetRealZoneText() }
    local pos = C_Map.GetPlayerMapPosition(ui, "player")
    if pos then
        local px, py = pos:GetXY()
        cur.inst, cur.wx, cur.wy = WorldPos(ui, px, py)
    end
    return cur
end

local function InZone(area, cur)
    if not cur then return false end
    return area == cur.area or (cur.area and zones.parent[area] == cur.area) or AreaUi(area) == cur.ui
end

local function Distance(cur, ui, x, y)
    if not (cur and cur.wx) then return nil end
    local inst, wx, wy = WorldPos(ui, x / 100, y / 100)
    if not inst or inst ~= cur.inst then return nil end
    local dx, dy = wx - cur.wx, wy - cur.wy
    return math.sqrt(dx * dx + dy * dy)
end

local function Better(a, b)
    if not b then return true end
    if a.here ~= b.here then return a.here end
    return (a.dist or huge) < (b.dist or huge)
end

-- Closest spawn in the current zone; otherwise (unless onlyHere) one in the NPC's main zone.
local function BestSpawn(spawns, cur, preferArea, onlyHere)
    if type(spawns) ~= "table" then return nil end
    local best, fallback
    for area, coords in pairs(spawns) do
        local ui = AreaUi(area)
        if ui and type(coords) == "table" then
            local here = InZone(area, cur)
            for _, c in ipairs(coords) do
                local x, y = c[1], c[2]
                if x and y and x >= 0 and y >= 0 then
                    if here then
                        local cand = { area = area, ui = ui, x = x, y = y, here = true, dist = Distance(cur, ui, x, y) }
                        if Better(cand, best) then best = cand end
                    elseif not onlyHere and (not fallback or (area == preferArea and fallback.area ~= preferArea)) then
                        fallback = { area = area, ui = ui, x = x, y = y }
                    end
                end
            end
        end
    end
    return best or fallback
end

----------------------------------------------------------------------------------------------
-- Lists
----------------------------------------------------------------------------------------------

local function HasDbObjectives(q)
    local o = LQ.Quest.objectives(q)
    if type(o) == "table" then
        for _, v in pairs(o) do
            if type(v) == "table" and next(v) then return true end
        end
    end
    return LQ.Quest.triggerEnd(q) ~= nil
end

local function ReadyForTurnIn(q)
    if C_QuestLog.IsFailed and C_QuestLog.IsFailed(q) then return false end
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) then return true end
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) then return true end
    -- "Deliver / talk to" quests have nothing to complete.
    local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q)
    if (not objs or #objs == 0) and LQ.Quest.Exists(q) and not HasDbObjectives(q) then return true end
    return false
end

local function CollectTurnIns(cur)
    local out = {}
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local q = info and not info.isHeader and info.questID
        if q and q > 0 and ReadyForTurnIn(q) then
            local e = { kind = "quest", quest = q, title = info.title or ("Quest " .. q), level = info.level }
            local fb = LQ.Quest.finishedBy(q)
            if type(fb) == "table" then
                local function consider(target)
                    local s = BestSpawn(target.spawns, cur, target.zone)
                    if s and Better(s, e.loc) then e.loc, e.who = s, target.name end
                    e.who = e.who or target.name
                end
                for _, id in ipairs(fb[1] or {}) do consider(NpcInfo(id)) end
                for _, id in ipairs(fb[2] or {}) do consider(ObjInfo(id)) end
            end
            if e.loc then e.loc.zoneName = ZoneName(e.loc.ui) end
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        local ah, bh = a.loc and a.loc.here or false, b.loc and b.loc.here or false
        if ah ~= bh then return ah end
        if ah then return (a.loc.dist or huge) < (b.loc.dist or huge) end
        local az = a.loc and a.loc.zoneName or "~"
        local bz = b.loc and b.loc.zoneName or "~"
        if az ~= bz then return az < bz end
        return a.title < b.title
    end)
    return out
end

-- Trainers and recipe vendors with a spawn in this zone (cached per map; distances recomputed).
local function ZoneCandidates(cur)
    local key = cur.ui
    local c = zoneCache[key]
    if c then return c end
    c = { trainers = {}, vendors = {} }
    if index.state ~= "ready" then return c end
    for _, t in ipairs(index.trainers) do
        if mySkills[t.skill] then
            local n = NpcInfo(t.id)
            if Friendly(n) and BestSpawn(n.spawns, cur, nil, true) then
                c.trainers[#c.trainers + 1] = { npc = n, skill = t.skill }
            end
        end
    end
    for vid, recs in pairs(index.vendors) do
        local relevant
        for _, r in ipairs(recs) do
            if mySkills[r.skill] then
                relevant = relevant or {}
                relevant[#relevant + 1] = r
            end
        end
        if relevant then
            local n = NpcInfo(vid)
            if Friendly(n) and BestSpawn(n.spawns, cur, nil, true) then
                c.vendors[#c.vendors + 1] = { npc = n, recipes = relevant }
            end
        end
    end
    zoneCache[key] = c
    return c
end

local KNOWN_TEXT = ITEM_SPELL_KNOWN
local function RecipeKnown(r)
    local cached = knownCache[r.id]
    if cached == true then return true end
    if cached and GetTime() - cached < 30 then return false end -- re-check unknown ones now and then
    local known = (r.spell and IsPlayerSpell and IsPlayerSpell(r.spell)) or false
    if not known and C_TooltipInfo and C_TooltipInfo.GetItemByID and KNOWN_TEXT then
        local data = C_TooltipInfo.GetItemByID(r.id)
        if data and data.lines then
            for _, l in ipairs(data.lines) do
                if l.leftText == KNOWN_TEXT then
                    known = true
                    break
                end
            end
        end
    end
    knownCache[r.id] = known or GetTime()
    return known
end

local function Learnable(id)
    if C_Item and C_Item.IsUsableItem then return C_Item.IsUsableItem(id) and true or false end
    return IsUsableItem and IsUsableItem(id) and true or false
end

local function ItemName(r)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(r.id)
    if not n and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(r.id) end
    return n or r.name or ("Item " .. r.id)
end

local function ByDistance(a, b)
    if (a.loc.dist or huge) ~= (b.loc.dist or huge) then return (a.loc.dist or huge) < (b.loc.dist or huge) end
    return a.name < b.name
end

-- What a trainer can teach you right now, from NaowhForever_Professions' RecipeData
-- (per-trainer recipe and rank lists with skill/level requirements). nil = cannot tell.
local RANK_LEVEL = { [150] = 10, [225] = 20, [300] = 35 }
local GATHERING = { [182] = true, [393] = true } -- no own data; ranks follow Mining's
local trainerIdx, spellKnown = {}, {}

local function NaowhData(line)
    local ns = _G.NaowhForever
    local rd = ns and ns.RecipeData
    if type(rd) ~= "table" then return nil end
    if rd[line] then return rd[line] end
    if GATHERING[line] and rd[186] then return { ranks = rd[186].ranks, gathering = true } end
end

local function TrainerIndex(data, line, npcId)
    local m = trainerIdx[line]
    if not m then
        m = {}
        for i, t in ipairs(data.trainers or {}) do m[t[1]] = i end
        trainerIdx[line] = m
    end
    return m[npcId]
end

local function Teaches(list, idx)
    if not list then return true end
    for _, v in ipairs(list) do
        if v == idx then return true end
    end
    return false
end

local function SpellKnown(spell)
    local c = spellKnown[spell]
    if c == true then return true end
    if c and GetTime() - c < 10 then return false end
    local known = (IsPlayerSpell and IsPlayerSpell(spell))
        or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(spell)) or false
    if not known and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spell)
        known = (ok and info and info.learned) and true or false
    end
    spellKnown[spell] = known or GetTime()
    return known
end

local function TrainerOffer(line, npcId)
    local data, sk = NaowhData(line), mySkills[line]
    if not (data and sk) then return nil end
    local idx = not data.gathering and TrainerIndex(data, line, npcId)
    if not data.gathering and not idx then return nil end
    local rank_, maxRank = sk.rank or 0, sk.max or 0
    local offer = { recipes = {}, cost = 0 }
    for _, r in ipairs(data.ranks or {}) do
        if r.cap > maxRank then
            if not r.item and not r.quest and rank_ >= r.skill
                and UnitLevel("player") >= (r.level or RANK_LEVEL[r.cap] or 0)
                and (data.gathering or Teaches(r.t, idx)) then
                offer.rank = r
                offer.cost = offer.cost + (r.cost or 0)
            end
            break
        end
    end
    if not data.gathering then
        for _, r in ipairs(data.recipes or {}) do
            if r.source == "trainer" and r.spell and (r.skill or 0) <= rank_ and Teaches(r.t, idx)
                and not SpellKnown(r.spell) then
                offer.recipes[#offer.recipes + 1] = r
                offer.cost = offer.cost + (r.cost or 0)
            end
        end
    end
    return offer
end

-- Recipe item -> Naowh recipe entry (exact skill requirement, craft spell, vendor prices).
local naowhRecipes
local function NaowhRecipe(itemId)
    if not naowhRecipes then
        local ns = _G.NaowhForever
        if not (ns and type(ns.RecipeData) == "table") then return nil end
        naowhRecipes = {}
        for _, data in pairs(ns.RecipeData) do
            for _, r in ipairs(data.recipes or {}) do
                if r.recipe then naowhRecipes[r.recipe] = r end
            end
        end
    end
    return naowhRecipes[itemId]
end

local function VendorPrice(nr, vendorId)
    for _, v in ipairs(nr and nr.vendors or {}) do
        if v[1] == vendorId then return v[7] end
    end
end

local function Money(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(copper / 10000, (copper / 100) % 100, copper % 100)
end

local function RankTitle(line, r)
    return r.name or ((({ [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" })[r.cap] or "New rank") .. " " .. SkillName(line))
end

local function CollectZone(cur)
    local cand = ZoneCandidates(cur)
    local trainers, vendors = {}, {}
    for _, t in ipairs(cand.trainers) do
        local offer = TrainerOffer(t.skill, t.npc.id)
        local worthIt = not offer or offer.rank or #offer.recipes > 0 -- unknown data: keep showing
        local loc = worthIt and BestSpawn(t.npc.spawns, cur, nil, true)
        if loc then
            trainers[#trainers + 1] = { kind = "trainer", name = t.npc.name, sub = t.npc.sub, skill = t.skill,
                offer = offer, loc = loc }
        end
    end
    for _, v in ipairs(cand.vendors) do
        local recipes = {}
        for _, r in ipairs(v.recipes) do
            -- Only recipes you do not know yet and can learn right now (skill high enough).
            -- Naowh's data gives the exact requirement; the game's IsUsableItem is only a fallback
            -- (it says "no" for recipes whose item data is not loaded yet).
            local name, nr = ItemName(r), NaowhRecipe(r.id)
            local learnable, known
            if nr then
                local sk = mySkills[r.skill]
                learnable = sk ~= nil and (sk.rank or 0) >= (nr.skill or 0)
                known = learnable and ((nr.spell and SpellKnown(nr.spell)) or RecipeKnown(r))
            else
                learnable = Learnable(r.id)
                known = learnable and RecipeKnown(r)
            end
            if learnable and not known then
                recipes[#recipes + 1] = { id = r.id, skill = r.skill, name = name, req = nr and nr.skill,
                    price = VendorPrice(nr, v.npc.id) }
            end
        end
        local loc = #recipes > 0 and BestSpawn(v.npc.spawns, cur, nil, true)
        if loc then
            table.sort(recipes, function(a, b) return a.name < b.name end)
            vendors[#vendors + 1] = { kind = "vendor", name = v.npc.name, sub = v.npc.sub, recipes = recipes, loc = loc }
        end
    end
    table.sort(trainers, ByDistance)
    table.sort(vendors, ByDistance)
    return trainers, vendors
end

----------------------------------------------------------------------------------------------
-- Waypoint
----------------------------------------------------------------------------------------------

local function SetWaypoint(e)
    local loc = e.loc
    if not loc then
        Print("no known location for " .. (e.who or e.name or "?") .. ".")
        return
    end
    local label = e.who or e.name
    local mapID, x, y = loc.ui, loc.x / 100, loc.y / 100
    -- Some maps (cities, sub-maps) do not take user waypoints: project onto the parent.
    for _ = 1, 4 do
        if not mapID or C_Map.CanSetUserWaypointOnMap(mapID) then break end
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        local minX, maxX, minY, maxY
        if parent and parent > 0 then minX, maxX, minY, maxY = C_Map.GetMapRectOnMap(mapID, parent) end
        if not minX then
            mapID = nil
            break
        end
        x, y = minX + x * (maxX - minX), minY + y * (maxY - minY)
        mapID = parent
    end
    local where = ("%s (%.1f, %.1f)"):format(ZoneName(loc.ui), loc.x, loc.y)
    if mapID and C_Map.CanSetUserWaypointOnMap(mapID) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
        Print("waypoint → " .. label .. ", " .. where)
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(loc.ui, loc.x / 100, loc.y / 100, { title = label, from = ADDON })
        Print("TomTom-waypoint → " .. label .. ", " .. where)
    else
        Print("can't set a waypoint here. " .. label .. ": " .. where)
    end
end

----------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------

local function FormatDist(loc)
    if loc.dist then return ("%d yd"):format(loc.dist + 0.5) end
    return ("%.0f, %.0f"):format(loc.x, loc.y)
end

local function QuestColor(level)
    local c = level and GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if c then return ("|cff%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255) end
    return "|cffffd100"
end

local function Header(key, text, count)
    model[#model + 1] = { header = true, key = key, text = text, count = count }
    return not db.collapsed[key]
end

local TURNIN_ICON = "Interface\\GossipFrame\\ActiveQuestIcon" -- yellow "?"
local summary = { here = 0, other = 0, trainers = 0, vendors = 0 }

local function BuildModel(cur)
    wipe(model)
    local quests = CollectTurnIns(cur)
    local here, other = {}, {}
    for _, q in ipairs(quests) do
        if q.loc and q.loc.here then here[#here + 1] = q else other[#other + 1] = q end
    end
    summary.here, summary.other, summary.trainers, summary.vendors = #here, #other, 0, 0
    -- Turn-ins in this zone get their own section on top, so they are impossible to miss.
    if #here > 0 and Header("questsHere", "|T" .. TURNIN_ICON .. ":14|t  Turn in here: " .. cur.name, #here) then
        for _, q in ipairs(here) do model[#model + 1] = q end
    end
    if Header("quests", #here > 0 and "Turn in elsewhere" or "Turn in", #other) then
        for _, q in ipairs(other) do model[#model + 1] = q end
    end
    if not cur then return end
    if index.state ~= "ready" then
        model[#model + 1] = { header = true, key = "loading",
            text = index.state == "error" and "|cffff5555Could not read QuestieDB|r" or "|cff999999Loading trainers and recipes…|r" }
        return
    end
    local trainers, vendors = CollectZone(cur)
    summary.trainers, summary.vendors = #trainers, #vendors
    if Header("trainers", "Trainers in " .. cur.name, #trainers) then
        for _, t in ipairs(trainers) do model[#model + 1] = t end
    end
    if Header("vendors", "Recipes in " .. cur.name, #vendors) then
        for _, v in ipairs(vendors) do model[#model + 1] = v end
    end
end

local function RowTooltip(row)
    local e = row.entry
    if not e or e.header then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if e.kind == "quest" then
        GameTooltip:AddLine(e.title)
        GameTooltip:AddLine("Turn in to " .. (e.who or "unknown"), 1, 1, 1)
    else
        GameTooltip:AddLine(e.name)
        if e.sub then GameTooltip:AddLine(e.sub, 1, 1, 1) end
    end
    if e.loc then
        GameTooltip:AddLine(("%s  %.1f, %.1f"):format(ZoneName(e.loc.ui), e.loc.x, e.loc.y), 0.7, 0.7, 0.7)
    end
    if e.kind == "trainer" and e.offer then
        GameTooltip:AddLine(" ")
        if e.offer.rank then
            GameTooltip:AddDoubleLine(RankTitle(e.skill, e.offer.rank), Money(e.offer.rank.cost or 0), 1, 0.82, 0, 1, 1, 1)
        end
        for k, r in ipairs(e.offer.recipes) do
            if k > 25 then
                GameTooltip:AddLine(("… and %d more"):format(#e.offer.recipes - 25), 0.7, 0.7, 0.7)
                break
            end
            local name = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(r.spell))
                or (GetSpellInfo and GetSpellInfo(r.spell)) or ("Spell " .. r.spell)
            GameTooltip:AddDoubleLine(name .. "  |cffaaaaaa(" .. (r.skill or 0) .. ")|r", Money(r.cost or 0), 0.2, 1, 0.2, 1, 1, 1)
        end
        GameTooltip:AddDoubleLine("Total", Money(e.offer.cost), 1, 1, 1, 1, 1, 1)
    elseif e.kind == "trainer" then
        GameTooltip:AddLine("No training data (NaowhForever Professions) for this trainer.", 0.7, 0.7, 0.7, true)
    end
    if e.kind == "vendor" then
        GameTooltip:AddLine(" ")
        for _, r in ipairs(e.recipes) do
            local label = r.name .. "  |cffaaaaaa" .. SkillName(r.skill) .. (r.req and (" " .. r.req) or "") .. "|r"
            GameTooltip:AddDoubleLine(label, r.price and Money(r.price) or "", 0.2, 1, 0.2, 1, 1, 1)
        end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(e.loc and "Click: set waypoint" or "Location missing from the database", 0.4, 0.8, 1)
    GameTooltip:Show()
end

-- Look: EllesmereUI's skinning API paints the window in the user's EUI theme (fonts, backdrop,
-- border, accent). Without EUI a flat fallback in the same spirit is drawn.
local EUI_ICONS = "Interface\\AddOns\\EllesmereUI\\media\\icons\\"
local hasEUI = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EllesmereUI")
local ICON = {
    close = hasEUI and EUI_ICONS .. "eui-close.png" or "Interface\\Buttons\\UI-StopButton",
    up = hasEUI and EUI_ICONS .. "eui-arrow-up3.png" or "Interface\\Buttons\\Arrow-Up-Up",
    down = hasEUI and EUI_ICONS .. "eui-arrow-down3.png" or "Interface\\Buttons\\Arrow-Down-Up",
    eye = hasEUI and EUI_ICONS .. "eui-visible.png" or "Interface\\Icons\\Spell_Shadow_Teleport",
    resize = hasEUI and EUI_ICONS .. "eui-resize-5.png" or "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up",
}
local OPACITY_STEPS = { 1, 0.75, 0.5, 0.25, 0 }
local skin -- EllesmereUI skin facade, when skinning is on
local fonts = {} -- every FontString we own, re-fonted by the skin

local function Accent()
    if skin and skin.GetAccentColor then return skin.GetAccentColor() end
    return 0.05, 0.82, 0.62 -- EllesmereUI's default teal
end

local function Hex(r, g, b)
    return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

local function Text(parent, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template)
    fonts[#fonts + 1] = fs
    if skin then skin.Font(fs) end
    return fs
end

local function IconButton(parent, texture, size, tooltip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexture(texture)
    b.icon:SetVertexColor(0.75, 0.75, 0.75)
    b:SetScript("OnEnter", function(self)
        self.icon:SetVertexColor(1, 1, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            tooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetVertexColor(0.75, 0.75, 0.75)
        GameTooltip:Hide()
    end)
    return b
end

local function CreateRow(i)
    local body = frame.body
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
    row:RegisterForClicks("LeftButtonUp")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    row.line1 = Text(row, "GameFontHighlight")
    row.line1:SetPoint("TOPLEFT", 4, -3)
    row.line1:SetPoint("RIGHT", -70, 0)
    row.line1:SetJustifyH("LEFT")
    row.line1:SetWordWrap(false)
    row.line2 = Text(row, "GameFontHighlightSmall")
    row.line2:SetPoint("TOPLEFT", row.line1, "BOTTOMLEFT", 0, -2)
    row.line2:SetPoint("RIGHT", -4, 0)
    row.line2:SetJustifyH("LEFT")
    row.line2:SetWordWrap(false)
    row.line2:SetTextColor(0.62, 0.62, 0.62)
    row.right = Text(row, "GameFontHighlightSmall")
    row.right:SetPoint("TOPRIGHT", -4, -4)
    row.right:SetJustifyH("RIGHT")
    row.right:SetTextColor(0.8, 0.8, 0.8)
    row.header = Text(row, "GameFontNormal")
    row.header:SetPoint("BOTTOMLEFT", 2, 6)
    row.rule = row:CreateTexture(nil, "ARTWORK")
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", 0, 3)
    row.rule:SetPoint("BOTTOMRIGHT", 0, 3)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if not e then return end
        if e.header then
            db.collapsed[e.key] = not db.collapsed[e.key] or nil
            Refresh()
        else
            SetWaypoint(e)
        end
    end)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

local function VisibleRows()
    return math.max(1, math.floor((frame.body:GetHeight() - BOTTOM) / ROW_H))
end

local function Render()
    if not frame.body:IsShown() then return end
    local visible = VisibleRows()
    offset = math.max(0, math.min(offset, #model - visible))
    local ar, ag, ab = Accent()
    for i = 1, math.max(visible, #rows) do
        local row = rows[i] or (i <= visible and CreateRow(i))
        local e = i <= visible and model[i + offset]
        if row then
            row.entry = e or nil
            row:SetShown(e and true or false)
            if e then
                local isHeader = e.header and true or false
                row.header:SetShown(isHeader)
                row.rule:SetShown(isHeader)
                row.line1:SetShown(not isHeader)
                row.line2:SetShown(not isHeader)
                row.right:SetShown(not isHeader)
                if isHeader then
                    local arrow = e.count and (db.collapsed[e.key] and "+  " or "–  ") or ""
                    if e.key == "questsHere" then
                        row.header:SetTextColor(1, 0.82, 0)
                        row.rule:SetColorTexture(1, 0.82, 0, 0.6)
                    else
                        row.header:SetTextColor(ar, ag, ab)
                        row.rule:SetColorTexture(ar, ag, ab, 0.35)
                    end
                    row.header:SetText(arrow .. e.text .. (e.count and ("  |cff888888" .. e.count .. "|r") or ""))
                elseif e.kind == "quest" then
                    local mark = (e.loc and e.loc.here) and ("|T" .. TURNIN_ICON .. ":14|t ") or ""
                    row.line1:SetText(mark .. QuestColor(e.level) .. "[" .. (e.level or "?") .. "]|r " .. e.title)
                    if e.loc then
                        row.line2:SetText((e.who or "?") .. " · " .. e.loc.zoneName)
                        row.right:SetText(e.loc.here and FormatDist(e.loc) or ("|cff888888" .. e.loc.zoneName .. "|r"))
                    else
                        row.line2:SetText((e.who or "Unknown NPC") .. " · location unknown")
                        row.right:SetText("")
                    end
                elseif e.kind == "trainer" then
                    row.line1:SetText(e.name .. "  |cff888888" .. (e.sub or "") .. "|r")
                    local o, parts = e.offer, {}
                    if o then
                        if o.rank then parts[#parts + 1] = Hex(ar, ag, ab) .. RankTitle(e.skill, o.rank) .. "|r" end
                        if #o.recipes > 0 then parts[#parts + 1] = "|cff33ff33" .. #o.recipes .. (#o.recipes == 1 and " new recipe|r" or " new recipes|r") end
                        parts[#parts + 1] = Money(o.cost)
                    else
                        parts[1] = SkillName(e.skill) .. " · can't tell what is trainable"
                    end
                    row.line2:SetText(table.concat(parts, " · "))
                    row.right:SetText(FormatDist(e.loc))
                else
                    local names = {}
                    for k, r in ipairs(e.recipes) do
                        if k > 4 then break end
                        names[#names + 1] = "|cff33ff33" .. r.name:gsub("^[^:]+: ", "") .. "|r"
                    end
                    row.line1:SetText(e.name .. "  |cff888888" .. #e.recipes .. (#e.recipes == 1 and " recipe|r" or " recipes|r"))
                    row.line2:SetText(table.concat(names, ", ") .. (#e.recipes > 4 and " …" or ""))
                    row.right:SetText(FormatDist(e.loc))
                end
            end
        end
    end
    -- Thin scroll thumb on the right edge, EUI-style.
    local total, thumb = #model, frame.thumb
    if total > visible then
        local track = visible * ROW_H
        local h = math.max(12, track * visible / total)
        thumb:SetHeight(h)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", frame.body, "TOPRIGHT", -3, -(track - h) * offset / (total - visible))
        thumb:Show()
        frame.status:SetText(("%d–%d of %d · scroll"):format(offset + 1, math.min(total, offset + visible), total))
    else
        thumb:Hide()
        frame.status:SetText("Click a row for a waypoint")
    end
end

function Refresh()
    if not (frame and frame:IsShown()) then return end
    local cur = CurrentZone()
    BuildModel(cur)
    local hereText = summary.here > 0 and ("|cffffd100" .. summary.here .. " to turn in here|r") or nil
    if db.windowCollapsed then
        local ar, ag, ab = Accent()
        local function part(label, n) return label .. " " .. Hex(ar, ag, ab) .. n .. "|r" end
        local parts = {}
        if hereText then parts[#parts + 1] = hereText end
        if summary.other > 0 then parts[#parts + 1] = part(hereText and "Elsewhere" or "Turn in", summary.other) end
        parts[#parts + 1] = part("Trainers", summary.trainers)
        parts[#parts + 1] = part("Recipes", summary.vendors)
        frame.sub:SetText(table.concat(parts, "   "))
    else
        frame.sub:SetText((cur and cur.name or "") .. (hereText and ("  ·  " .. hereText) or ""))
    end
    -- Pulsing quest icon in the title bar while something can be turned in in this zone.
    local show = summary.here > 0
    if show ~= frame.questIcon:IsShown() then
        frame.questIcon:SetShown(show)
        frame.title:ClearAllPoints()
        frame.title:SetPoint("LEFT", show and (PAD + 22) or (PAD + 2), 0)
        if show then frame.questPulse:Play() else frame.questPulse:Stop() end
    end
    Render()
end

local pending
local function RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        Refresh()
    end)
end

local function ApplyOpacity()
    frame.bg:SetAlpha(db.opacity or 1)
end

local function ApplyCollapsed()
    local c = db.windowCollapsed and true or false
    frame.body:SetShown(not c)
    if frame.SetResizeBounds then frame:SetResizeBounds(300, c and BAR_H or 200, 700, 1000) end
    frame:SetHeight(c and BAR_H or (db.height or 440))
    frame.fold.icon:SetTexture(c and ICON.down or ICON.up)
    Refresh()
end

local function ToggleCollapsed()
    db.windowCollapsed = not db.windowCollapsed or nil
    ApplyCollapsed()
end

local function SavePosition()
    db.left, db.top = frame:GetLeft(), frame:GetTop()
end

local function PaintFallback(bg)
    local fill = bg:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetAllPoints()
    fill:SetColorTexture(0.06, 0.06, 0.07, 0.88)
    local bar = bg:CreateTexture(nil, "BACKGROUND", nil, -5)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:SetColorTexture(0, 0, 0, 0.5)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }) do
        local t = bg:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0, 0, 0, 1)
        t:SetPoint(side[1])
        t:SetPoint(side[2])
        if side[3] == 1 then t:SetWidth(1) else t:SetHeight(1) end
    end
end

local function CreateMainFrame()
    frame = CreateFrame("Frame", "WhatsHereFrame", UIParent)
    frame:SetSize(db.width or 380, db.windowCollapsed and BAR_H or (db.height or 440))
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "RIGHT", -120, 260)
    end
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    if frame.SetResizeBounds then
        frame:SetResizeBounds(300, 200, 700, 1000)
    elseif frame.SetMinResize then
        frame:SetMinResize(300, BAR_H)
    end
    local level = frame:GetFrameLevel()

    -- Backdrop on its own child so the opacity setting fades only the background, never the text.
    frame.bg = CreateFrame("Frame", nil, frame)
    frame.bg:SetAllPoints()
    frame.bg:SetFrameLevel(level)
    PaintFallback(frame.bg)

    -- Title bar: drag to move, click to fold the list up/down.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_H)
    bar:SetFrameLevel(level + 3)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    local dragged
    bar:SetScript("OnDragStart", function()
        dragged = true
        frame:StartMoving()
    end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    end)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" and not dragged then ToggleCollapsed() end
        dragged = false
    end)

    local title = Text(bar, "GameFontNormal")
    title:SetPoint("LEFT", PAD + 2, 0)
    title:SetText("What's Here")
    frame.title = title
    frame.questIcon = bar:CreateTexture(nil, "OVERLAY")
    frame.questIcon:SetSize(16, 16)
    frame.questIcon:SetPoint("LEFT", PAD, 0)
    frame.questIcon:SetTexture(TURNIN_ICON)
    frame.questIcon:Hide()
    frame.questPulse = frame.questIcon:CreateAnimationGroup()
    frame.questPulse:SetLooping("BOUNCE")
    local fade = frame.questPulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.8)
    frame.sub = Text(bar, "GameFontHighlightSmall")
    frame.sub:SetPoint("LEFT", title, "RIGHT", 8, 0)
    frame.sub:SetPoint("RIGHT", bar, "RIGHT", -70, 0)
    frame.sub:SetJustifyH("LEFT")
    frame.sub:SetWordWrap(false)
    frame.sub:SetTextColor(0.7, 0.7, 0.7)

    local close = IconButton(bar, ICON.close, 12, function(tt) tt:AddLine("Hide the list  (/wh brings it back)") end)
    close:SetPoint("RIGHT", -8, 0)
    close:SetScript("OnClick", function()
        db.shown = false
        frame:Hide()
    end)

    frame.fold = IconButton(bar, ICON.up, 12, function(tt)
        tt:AddLine(db.windowCollapsed and "Expand the list" or "Collapse the list")
        tt:AddLine("You can also click the title bar", 0.7, 0.7, 0.7)
    end)
    frame.fold:SetPoint("RIGHT", close, "LEFT", -8, 0)
    frame.fold:SetScript("OnClick", ToggleCollapsed)

    local eye = IconButton(bar, ICON.eye, 14, function(tt)
        tt:AddLine(("Background: %d %%"):format((db.opacity or 1) * 100 + 0.5))
        tt:AddLine("Click: change transparency", 0.7, 0.7, 0.7)
        tt:AddLine("Mouse wheel: fine-tune", 0.7, 0.7, 0.7)
    end)
    eye:SetPoint("RIGHT", frame.fold, "LEFT", -8, 0)
    eye:SetScript("OnClick", function(self)
        local cur, nextStep = db.opacity or 1, OPACITY_STEPS[1]
        for i, v in ipairs(OPACITY_STEPS) do
            if cur > v + 0.01 then
                nextStep = v
                break
            end
            if i == #OPACITY_STEPS then nextStep = OPACITY_STEPS[1] end
        end
        db.opacity = nextStep
        ApplyOpacity()
        self:GetScript("OnEnter")(self)
    end)
    eye:EnableMouseWheel(true)
    eye:SetScript("OnMouseWheel", function(self, delta)
        db.opacity = math.max(0, math.min(1, (db.opacity or 1) + delta * 0.05))
        ApplyOpacity()
        self:GetScript("OnEnter")(self)
    end)

    -- Body: rows, footer, scroll thumb and resize grip; hidden when folded.
    local body = CreateFrame("Frame", nil, frame)
    body:SetPoint("TOPLEFT", 0, -(BAR_H + 6))
    body:SetPoint("BOTTOMRIGHT")
    body:SetFrameLevel(level + 2)
    frame.body = body
    body:EnableMouse(true) -- clicks between rows must not fall through to the world

    frame.status = Text(body, "GameFontHighlightSmall")
    frame.status:SetPoint("BOTTOMLEFT", PAD + 2, 7)
    frame.status:SetTextColor(0.5, 0.5, 0.5)

    frame.thumb = body:CreateTexture(nil, "OVERLAY")
    frame.thumb:SetWidth(2)
    frame.thumb:SetColorTexture(1, 1, 1, 0.45)
    frame.thumb:Hide()

    local grip = IconButton(body, ICON.resize, 12)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        db.width, db.height = frame:GetSize()
        SavePosition()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
        Render()
    end)
    frame:SetScript("OnSizeChanged", function() if #model > 0 then Render() end end)

    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta * 2
        Render()
    end)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed > 3 then -- keep distances fresh while open
            elapsed = 0
            Refresh()
        end
    end)
    frame:SetScript("OnShow", Refresh)

    ApplyOpacity()
    body:SetShown(not db.windowCollapsed)
    frame.fold.icon:SetTexture(db.windowCollapsed and ICON.down or ICON.up)
    if db.windowCollapsed and frame.SetResizeBounds then frame:SetResizeBounds(300, BAR_H, 700, 1000) end
    frame:Hide()

    if EllesmereUI and EllesmereUI.RegisterSkin then
        EllesmereUI.RegisterSkin(ADDON, function(S)
            skin = S
            S.Shell(frame.bg) -- fades the fallback art and paints the EUI backdrop, title strip and border
            for _, fs in ipairs(fonts) do S.Font(fs) end
            if S.OnLooksChanged then S.OnLooksChanged(Refresh) end
            Refresh()
        end)
    end
end

function WhatsHere_Toggle()
    if not frame then return end
    db.shown = not frame:IsShown()
    frame:SetShown(db.shown)
end

BINDING_HEADER_WHATSHERE = "What's Here"
BINDING_NAME_WHATSHERE_TOGGLE = "Show/hide What's Here"

local function RegisterLauncher()
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end
    local obj = LDB:NewDataObject("WhatsHere", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
        OnClick = WhatsHere_Toggle,
        OnTooltipShow = function(tt)
            tt:AddLine("What's Here")
            tt:AddLine("Click: show/hide the list", 1, 1, 1)
        end,
    })
    local icon = LibStub("LibDBIcon-1.0", true)
    if icon and obj then
        db.minimap = db.minimap or {}
        icon:Register("WhatsHere", obj, db.minimap)
    end
end

----------------------------------------------------------------------------------------------
-- Events
----------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            WhatsHereDB = WhatsHereDB or {}
            db = WhatsHereDB
            if db.shown == nil then db.shown = true end -- first install: open straight away
            db.collapsed = db.collapsed or {}
            db.allProfessions, db.point = nil, nil -- removed options
        end
        return
    end
    if event == "PLAYER_LOGIN" then
        if not (LQ and LQ.Npc and LQ.Item and LQ.Quest) then
            Print("QuestieDB is missing or too old – addon disabled.")
            return
        end
        playerFaction = UnitFactionGroup("player") == "Horde" and "H" or "A"
        LoadZones()
        ScanProfessions()
        CreateMainFrame()
        RegisterLauncher()
        for _, ev in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "PLAYER_ENTERING_WORLD",
            "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_ACCEPTED", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB",
            "NEW_RECIPE_LEARNED", "TRADE_SKILL_LIST_UPDATE", "GET_ITEM_INFO_RECEIVED", "TRAINER_CLOSED",
            "PLAYER_LEVEL_UP" }) do
            pcall(events.RegisterEvent, events, ev)
        end
        C_Timer.After(5, BuildIndex) -- let Questie finish its own startup first
        if db.shown then frame:Show() end
        return
    end
    if event == "SKILL_LINES_CHANGED" or event == "LEARNED_SPELL_IN_TAB" or event == "NEW_RECIPE_LEARNED"
        or event == "TRAINER_CLOSED" or event == "TRADE_SKILL_LIST_UPDATE" then
        ScanProfessions()
        for k, v in pairs(spellKnown) do
            if v ~= true then spellKnown[k] = nil end
        end
    end
    RequestRefresh()
end)

SLASH_WHATSHERE1 = "/whatshere"
SLASH_WHATSHERE2 = "/wh"
SlashCmdList.WHATSHERE = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not frame then return end
    if msg == "reset" then
        db.left, db.top, db.width, db.height, db.opacity, db.windowCollapsed = nil, nil, nil, nil, nil, nil
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "RIGHT", -120, 260)
        frame:SetSize(380, 440)
        frame.bg:SetAlpha(1)
        frame.body:Show()
        frame.fold.icon:SetTexture(ICON.up)
        db.shown = true
        frame:Show()
    elseif msg == "status" then
        local nv = 0
        for _ in pairs(index.vendors) do nv = nv + 1 end
        Print(("index: %s, %d trainers, %d recipe vendors."):format(index.state, #index.trainers, nv))
    else
        WhatsHere_Toggle()
    end
end
