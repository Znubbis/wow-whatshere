dofile(arg[2] .. "/encoding.lua")
local LQ = dofile(arg[2] .. "/harness.lua")
local N, I = LQ.Npc, LQ.Item
local name = arg[3]
for _, id in ipairs(N.GetAllIds()) do
  local n = N.name(id)
  if n and n:lower():find(name:lower(), 1, true) then
    print("NPC", id, n, N.subName(id), "flags", N.npcFlags(id), "faction", N.friendlyToFaction(id), "zoneID", N.zoneID(id))
    for a, c in pairs(N.spawns(id) or {}) do print("  spawn area", a, c[1][1], c[1][2]) end
  end
end
for _, id in ipairs(I.GetAllIds()) do
  local n = I.name(id)
  if n and n:find("Nature Protection") then
    local v = I.vendors(id)
    print("ITEM", id, n, "class", I.class(id), "sub", I.subClass(id), "spell", I.teachesSpell(id), "vendors", v and table.concat(v, ","))
  end
end
