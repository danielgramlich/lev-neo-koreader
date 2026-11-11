-- Lev Neo (2026-11-11): tela de Ajustes do ZenOS com a barra de baixo e sem a logo.
-- * A tela de Ajustes ocupava a tela toda e escondia a barra de baixo do Lev. Agora ela e
--   montada com a altura da tela menos a barra; tocar na barra fecha os Ajustes e segue
--   para a aba tocada.
-- * Some a logo do ZenOS ao lado do titulo "Settings" (e o espaco dela).
-- * A barra de baixo marca a aba Settings enquanto os Ajustes estao abertos.
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
        -- sem a logo, a caixa dela (e o espaco depois) some na tela principal dos Ajustes;
        -- nas subtelas ela volta para a seta de voltar. A largura vai para o titulo, para
        -- a lupa e o X nao mudarem de lugar.
        local function recolher(tb)
            local lc, linha, tc = tb.leading_container, tb._header_row, tb.title_container
            if not (lc and lc.dimen and linha and tc and tc.dimen) then return end
            if not tb._lev_lw then
                tb._lev_lw = lc.dimen.w
                for i, w in ipairs(linha) do
                    if w == lc and linha[i + 1] and type(linha[i + 1].width) == "number" then
                        tb._lev_sp, tb._lev_spw = linha[i + 1], linha[i + 1].width
                        break
                    end
                end
            end
            local delta = tb._lev_lw + (tb._lev_spw or 0)
            local recolher_agora = tb.back_visible ~= true
            if recolher_agora and not tb._lev_recolhido then
                lc.dimen.w = 0
                if tb._lev_sp then tb._lev_sp.width = 0 end
                tc.dimen.w = tc.dimen.w + delta
                tb._lev_recolhido = true
            elseif not recolher_agora and tb._lev_recolhido then
                lc.dimen.w = tb._lev_lw
                if tb._lev_sp then tb._lev_sp.width = tb._lev_spw end
                tc.dimen.w = math.max(1, tc.dimen.w - delta)
                tb._lev_recolhido = false
            end
            if linha.resetLayout then linha:resetLayout() end
        end
        local initTitulo = TitleBar.init
        TitleBar.init = function(self, ...)
            local r = { initTitulo(self, ...) }
            if self.root_icon then self.root_icon.paintTo = function() end end
            pcall(recolher, self)
            return unpack(r)
        end
        if type(TitleBar.setState) == "function" then
            local estado = TitleBar.setState
            TitleBar.setState = function(self, ...)
                local r = { estado(self, ...) }
                pcall(recolher, self)
                return unpack(r)
            end
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
        -- a barra de baixo com "Settings" sublinhado (copia da barra pintada por cima)
        local pintarPagina = self.paintTo
        self.paintTo = function(pagina, bb, x, y, ...)
            local r = { pintarPagina(pagina, bb, x, y, ...) }
            local B = rawget(_G, "__LEV_BARRA")
            if B and B.pintar then pcall(B.pintar, bb, "lev_ajustes") end
            return unpack(r)
        end
        UIManager:setDirty(nil, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = H })
        self.onLevTapBarra = function(pagina, _arg, ges)
            if pagina.closeMenu then pcall(pagina.closeMenu, pagina) else UIManager:close(pagina) end
            UIManager:nextTick(function() UIManager:sendEvent(Event:new("Gesture", ges)) end)
            return true
        end
    end
    logger.info("Lev: Ajustes com a barra de baixo e sem logo")
end)
