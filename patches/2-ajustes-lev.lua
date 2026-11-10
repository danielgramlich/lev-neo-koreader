-- Lev Neo (2026-11-06): botoes "the news" e "Ajustes" na barra inferior do ZenOS.
-- Acrescenta ao plugin ZenOS dois metodos, chamados por abas personalizadas
-- (custom tabs do tipo "plugin" em settings/ZenOS/config.lua, navbar.custom_tabs):
--   levAbrirTheNews : abre direto a edicao mais recente de /mnt/fat/the news e tenta,
--                     em segundo plano, baixar uma edicao mais nova
--   levAbrirAjustes : abre a tela de Ajustes do ZenOS (a mesma do menu)
-- Para desfazer: apague este arquivo e as abas "lev_thenews"/"lev_ajustes" da configuracao.
local userpatch = require("userpatch")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local PASTA_THENEWS = "/mnt/fat/the news"

-- Edicao mais recente pela data no nome do arquivo (AA-MM-DD_HH-MM_...)
local function edicaoMaisRecente()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(PASTA_THENEWS, "mode") ~= "directory" then return nil end
    local melhor_chave, melhor_nome
    for nome in lfs.dir(PASTA_THENEWS) do
        if nome:match("%.epub$") then
            local chave = nome:match("^(%d%d%-%d%d%-%d%d_%d%d%-%d%d)") or ""
            if not melhor_chave or chave > melhor_chave then
                melhor_chave, melhor_nome = chave, nome
            end
        end
    end
    return melhor_nome and (PASTA_THENEWS .. "/" .. melhor_nome) or nil
end

userpatch.registerPatchPluginFunc("zenos", function(plugin)
    plugin.levAbrirAjustes = function(self)
        UIManager:scheduleIn(0, function()
            local ok, page = pcall(require, "modules/settings/zen_settings_page")
            if ok and page and page.show then
                page.show(self)
            else
                logger.warn("Lev: nao achei a tela de Ajustes do ZenOS")
            end
        end)
        return true
    end

    plugin.levAbrirTheNews = function(self)
        -- tenta trazer a edicao mais nova em segundo plano (sem travar a tela)
        local baixar = rawget(_G, "__LEV_JORNAL_SEGUNDO_PLANO")
        if type(baixar) == "function" then baixar() end
        UIManager:scheduleIn(0, function()
            local arquivo = edicaoMaisRecente()
            if arquivo then
                require("apps/reader/readerui"):showReader(arquivo)
            else
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{ text = "Downloading the latest the news…", timeout = 3 })
            end
        end)
        return true
    end
end)

logger.info("Lev: botoes the news e Ajustes ativos")
