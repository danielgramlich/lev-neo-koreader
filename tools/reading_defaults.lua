-- Reading defaults tuned for the Lev's ~212 ppi panel, applied to the global settings
-- and to every book already opened. Also sets the dictionary order (EN->PT first).
-- Run on the device from /mnt/fat/koreader with KOReader stopped or right before
-- `kill -9 $(pidof luajit)` (KOReader rewrites settings when it exits normally):
--   ./luajit /tmp/reading_defaults.lua [library folder, default /mnt/fat]
require("setupkoenv")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")
local LIB = arg[1] or "/mnt/fat"
local DEFAULTS = {
    copt_font_base_weight = 0.5,  -- slightly heavier strokes
    copt_font_gamma = 25,         -- darker text
    copt_font_hinting = 2,        -- auto hinting
    copt_font_kerning = 3,        -- best kerning
    copt_line_spacing = 120,      -- 1.2 line height
    copt_h_page_margins = { 40, 40 },
    copt_t_page_margin = 18,
    copt_b_page_margin = 18,
}
local function apply(file)
    local s = LuaSettings:open(file)
    for k, v in pairs(DEFAULTS) do s:saveSetting(k, v) end
    s:flush()
end
apply("/mnt/fat/koreader/settings.reader.lua")
-- keys must match KOReader's data dir as seen by sdcv: STARDICT_DATA_DIR="data/dict" (koreader.sh)
local g = LuaSettings:open("/mnt/fat/koreader/settings.reader.lua")
local D = "data/dict/"
g:saveSetting("dicts_order", { [D .. "en-pt/en-pt.ifo"] = 1, [D .. "eng-por/eng-por.ifo"] = 2,
    [D .. "en-en/English-English Wiktionary dictionary.ifo"] = 3 })
g:flush()
local n = 0
for name in lfs.dir(LIB) do
    if name:match("%.sdr$") and not name:match("^%.") then
        for f in lfs.dir(LIB .. "/" .. name) do
            if f:match("^metadata%.%w+%.lua$") then apply(LIB .. "/" .. name .. "/" .. f); n = n + 1 end
        end
    end
end
print("books updated:", n)
