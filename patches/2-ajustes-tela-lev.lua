-- Lev Neo (2026-11-11): tela de Ajustes do ZenOS com a barra de baixo e sem a logo.
-- * A tela de Ajustes ocupava a tela toda e escondia a barra de baixo do Lev. Agora ela e
--   montada com a altura da tela menos a barra; tocar na barra fecha os Ajustes e segue
--   para a aba tocada.
-- * Some a logo do ZenOS ao lado do titulo "Settings".
-- Para desfazer: apague este arquivo (koreader/patches/2-ajustes-tela-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")

userpatch.registerPatchPluginFunc("zenos", function()
    local Device = require("device")
    local Event = require("ui/event")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local UIManager = require("ui/uimanager")
    local Screen = Device.screen

    -- sem a logo no titulo
    local okT, TitleBar = pcall(require, "common/ui/zen_settings_titlebar")
    if okT and type(TitleBar) == "table" and type(TitleBar.init) == "function" and not TitleBar._lev_sem_logo then
        TitleBar._lev_sem_logo = true
        local initTitulo = TitleBar.init
        TitleBar.init = function(self, ...)
            local r = { initTitulo(self, ...) }
            if self.root_icon then self.root_icon.paintTo = function() end end
            return unpack(r)
        end
    end

    -- Ajustes acima da barra de baixo
    local okP, Pagina = pcall(require, "modules/settings/zen_settings_page")
    local Page = okP and type(Pagina) == "table" and Pagina.Page
    if type(Page) ~= "table" or type(Page.init) ~= "function" or Page._lev_barra then
        if type(Page) ~= "table" then logger.warn("Lev ajustes: tela de Ajustes do ZenOS nao encontrada") end
        return
    end
    Page._lev_barra = true
    local initPagina = Page.init
    Page.init = function(self, ...)
        local barra = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
        local H = Screen:getHeight()
        if barra <= 0 or barra > H / 3 then return initPagina(self, ...) end
        -- durante a montagem, a tela "termina" em cima da barra
        local alturaOriginal = Screen.getHeight
        Screen.getHeight = function(s) return alturaOriginal(s) - barra end
        local ok, err = pcall(initPagina, self, ...)
        Screen.getHeight = alturaOriginal
        if not ok then error(err) end
        self.covers_fullscreen = false
        -- toque na barra: fecha os Ajustes e repassa o toque para a barra
        self.ges_events = self.ges_events or {}
        self.ges_events.LevTapBarra = { GestureRange:new{ ges = "tap",
            range = Geom:new{ x = 0, y = H - barra, w = Screen:getWidth(), h = barra } } }
        self.onLevTapBarra = function(pagina, _arg, ges)
            if pagina.closeMenu then pcall(pagina.closeMenu, pagina) else UIManager:close(pagina) end
            UIManager:nextTick(function() UIManager:sendEvent(Event:new("Gesture", ges)) end)
            return true
        end
    end
    logger.info("Lev: Ajustes com a barra de baixo e sem logo")
end)
