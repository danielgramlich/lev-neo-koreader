-- Lev Neo (2026-11-06): troca o logo do ZenOS no botao de configuracao do menu
-- suspenso (canto superior esquerdo) por uma engrenagem de traco fino.
-- A aba "Ajustes" da barra inferior usa o icone lev_ajustes.svg (tres listras),
-- definido em settings/ZenOS/config.lua (navbar.custom_tabs).
-- Tambem tira o fundo preto do icone de aba que ja vem selecionado (foco dos botoes)
-- ao abrir o menu suspenso; a aba atual continua marcada pelo sublinhado do menu.
-- Para desfazer: apague este arquivo (koreader/patches/2-icones-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")

local ENGRENAGEM = DataStorage:getDataDir() .. "/icons/lev_engrenagem.svg"
local TROCAR = {
    _zen_settings_tab = true, -- botao de configuracao do ZenOS no menu suspenso
    _zen_update_tab = true,   -- o mesmo botao quando ha atualizacao do ZenOS
}

-- aplicado depois que o ZenOS carregou (ele tambem embrulha IconWidget.init;
-- o nosso precisa ficar por fora para valer por ultimo)
userpatch.registerPatchPluginFunc("zenos", function()
    if lfs.attributes(ENGRENAGEM, "mode") ~= "file" then
        logger.warn("Lev: icone da engrenagem nao encontrado:", ENGRENAGEM)
        return
    end
    local IconWidget = require("ui/widget/iconwidget")
    local init_original = IconWidget.init
    function IconWidget:init()
        init_original(self)
        if TROCAR[self.icon] then self.file = ENGRENAGEM end
    end
    logger.info("Lev: icone de configuracao do menu trocado (engrenagem)")

    local TouchMenu = require("ui/widget/touchmenu")
    local semFundo = function(btn)
        if btn.image then btn.image.invert = false end
        return true
    end
    local init_menu = TouchMenu.init
    function TouchMenu:init(...)
        init_menu(self, ...)
        for _, btn in ipairs(self.bar and self.bar.icon_widgets or {}) do
            btn.onFocus = semFundo
            btn.onUnfocus = semFundo
            if btn.image then btn.image.invert = false end
        end
    end
    logger.info("Lev: abas do menu sem fundo preto no foco")
end)
