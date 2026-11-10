-- Adds the "Auto night" button (patches/2-noite-lev.lua) to the ZenOS quick settings,
-- right after "Night". Safe to run more than once. Skips if ZenOS is not configured yet.
require("setupkoenv")
local lfs = require("libs/libkoreader-lfs")
local arq = "/mnt/fat/koreader/settings/ZenOS/config.lua"
if not lfs.attributes(arq) then print("ZenOS config not found; open ZenOS once and rerun") return end
local s = require("luasettings"):open(arq)
local qs = s:readSetting("quick_settings")
if type(qs) ~= "table" or type(qs.button_order) ~= "table" then print("ZenOS quick settings not found") return end
qs.custom_buttons = qs.custom_buttons or {}
local tem = false
for _, b in ipairs(qs.custom_buttons) do if b.id == "lev_noite_auto" then tem = true end end
if not tem then
    table.insert(qs.custom_buttons, { id = "lev_noite_auto", label = "Auto night", icon = "lev_noite_auto",
        action = { lev_noite_auto = true } })
end
local ordem, posto = {}, false
for _, id in ipairs(qs.button_order) do
    if id ~= "lev_noite_auto" then table.insert(ordem, id) end
    if id == "night" then table.insert(ordem, "lev_noite_auto"); posto = true end
end
if not posto then table.insert(ordem, "lev_noite_auto") end
qs.button_order = ordem
s:saveSetting("quick_settings", qs)
s:flush()
print("quick settings: " .. table.concat(ordem, ", "))
