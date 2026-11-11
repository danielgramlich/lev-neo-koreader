-- Lev Neo (2026-11-11): baixador leve do the news, fora do KOReader.
-- Roda como processo novo (./luajit lev_baixar_jornal.lua) em vez de copiar o KOReader
-- inteiro (fork de ~220 MB), que estourava a memoria do Lev em edicoes grandes.
-- Usa o proprio plugin News Downloader (rede e montagem do EPUB); as telas dele sao
-- trocadas por versoes vazias. Le /mnt/fat/feed_config.lua e grava em /mnt/fat/<feed>/.
-- Nunca grava settings.reader.lua (so le).
require("setupkoenv")
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir() .. "/settings.reader.lua")
G_reader_settings.flush = function() end -- somente leitura neste processo
G_defaults = require("luadefaults"):open()

local function vazio()
    return setmetatable({}, { __index = function() return function() end end })
end
for _, m in ipairs{ "ui/widget/infomessage", "ui/uimanager", "ui/widget/keyvaluepage",
        "ui/widget/inputdialog", "ui/widget/multiconfirmbox", "ui/network/manager",
        "feed_view", "readhistory", "document/documentregistry" } do
    package.loaded[m] = vazio()
end
-- sem aparelho e sem telas: nada de abrir tela, toque ou botoes neste processo
package.loaded["device"] = setmetatable({ model = "Lev", screen = vazio(), input = vazio() },
    { __index = function() return function() return false end end })
package.loaded["ui/trapper"] = {
    info = function() return true end,             -- "continuar"
    confirm = function() return true end,          -- sempre "OK" (como o Trapper sem tela)
    clear = function() end, reset = function() end,
    wrap = function(_, f) return f() end,
    dismissableRunInSubprocess = function(_, f) return true, f() end,
}
package.loaded["ui/bidi"] = setmetatable({}, { __index = function() return function(x) return x end end })
package.loaded["ui/widget/container/widgetcontainer"] = {
    extend = function(self, o) o = o or {}; return setmetatable(o, { __index = self }) end,
}

local PLUGIN = "plugins/newsdownloader.koplugin/"
package.path = PLUGIN .. "?.lua;" .. package.path
local ND = dofile(PLUGIN .. "main.lua")
ND.download_dir = arg[1] or "/mnt/fat/"

local feeds = dofile(arg[2] or "/mnt/fat/feed_config.lua")
local erros = 0
for _, f in ipairs(feeds) do
    if type(f) == "table" and type(f[1]) == "string" then
        local ok, err = pcall(ND.processFeedSource, ND, f[1], f.credentials, f.http_auth, f.limit or 0, {},
            f.download_full_article, f.include_images, "", f.enable_filter, f.filter_element,
            f.block_element, f.max_age)
        if not ok then erros = erros + 1; io.stderr:write("feed falhou: ", tostring(err), "\n") end
    end
end
print(erros == 0 and "ok" or ("erros: " .. erros))
os.exit(erros == 0 and 0 or 1)
