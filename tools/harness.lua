-- Offline loader for baked QuestieDB: emulates C_AddOns.GetAddOnMetadata from the TOC.
local dir = arg[1]
local toc = dir .. "/QuestieDB_Forever.toc"
local meta, files = {}, {}
for line in io.lines(toc) do
  local k, v = line:match("^## ([^:]+): ?(.*)$")
  if k then meta[k] = v
  elseif line:match("^[^#%s]") then files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", "")) end
end
C_AddOns = { GetAddOnMetadata = function(_, key) return meta[key] end }
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
strsplit = function(sep, s) local out = {} for p in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out+1] = p end return unpack(out) end
UnitFactionGroup = function() return "Horde", "Horde" end
UnitClassBase = function() return "WARRIOR", 1 end
UnitRace = function() return "Orc", "Orc", 2 end
UnitLevel = function() return 30 end
GetLocale = function() return "enUS" end
GetBuildInfo = function() return "1.60.1", "71037", "Nov 2026", 16001 end
WOW_PROJECT_ID = 99; WOW_PROJECT_CLASSIC = 2; WOW_PROJECT_MAINLINE = 1
debugprofilestop = function() return os.clock() * 1000 end
local ns = {}
for _, f in ipairs(files) do
  local chunk, err = loadfile(dir .. "/" .. f)
  if not chunk then error(f .. ": " .. err) end
  local ok, e = pcall(chunk, "QuestieDB", ns)
  if not ok then error(f .. ": " .. tostring(e)) end
end
return ns
