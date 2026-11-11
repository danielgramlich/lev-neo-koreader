-- Lev Neo (2026-11-11): menu de acesso rapido sem a barra de cima.
-- Esconde a barra de abas do menu (icones de ajustes rapidos, apps, engrenagem e Inicio):
-- ela deixa de ser desenhada e nao ocupa espaco. O menu sempre abre nos Ajustes rapidos.
-- Inicio, Biblioteca e Ajustes continuam na barra de baixo do Lev.
-- Tambem sobe 2 px a linha de hora, Wi-Fi e bateria, deixa a borda do menu fina (1 px cinza)
-- e desfoca o resto da tela enquanto o menu esta aberto.
-- Para desfazer: apague este arquivo (koreader/patches/2-menu-lev.lua).
local Geom = require("ui/geometry")
local TouchMenu = require("ui/widget/touchmenu")
local logger = require("logger")

local function esconderBarra(menu)
    local bar = menu.bar
    if not bar or bar._lev_oculta then return false end
    bar._lev_oculta = true
    bar.getSize = function() return Geom:new{ w = 0, h = 0 } end
    bar.paintTo = function(self, _bb, x, y) self.dimen = Geom:new{ x = x, y = y, w = 0, h = 0 } end
    bar.handleEvent = function() return false end -- sem toques numa barra invisivel
    return true
end

-- sobe 2 px a linha de hora / Wi-Fi / bateria (tira 2 px do espaco de cima e poe embaixo,
-- para os botoes nao mudarem de lugar)
local SUBIR = 2
local function subirStatus(menu)
    local refs = menu._zen_panel_refs
    local sr = refs and refs.status_row
    local painel = sr and sr.parent
    if not painel or painel._lev_status_subiu or not sr.index then return end
    local antes, depois = painel[sr.index - 1], painel[sr.index + 1]
    if antes and depois and type(antes.width) == "number" and type(depois.width) == "number"
            and antes.width > SUBIR then
        antes.width = antes.width - SUBIR
        depois.width = depois.width + SUBIR
        painel._lev_status_subiu = true
        if painel.resetLayout then painel:resetLayout() end
    end
end

-- fundo desfocado enquanto o menu esta aberto (aparece junto com o menu, numa atualizacao so)
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local function desfocar(bb)
    local mupdf = require("ffi/mupdf")
    local W, H = bb:getWidth(), bb:getHeight()
    local copia = Blitbuffer.new(W, H, Blitbuffer.TYPE_BB8)
    copia:blitFrom(bb, 0, 0, 0, 0, W, H)
    local peq = mupdf.scaleBlitBuffer(copia, math.max(1, math.floor(W / 7)), math.max(1, math.floor(H / 7)))
    copia:free()
    local grande = mupdf.scaleBlitBuffer(peq, W, H)
    peq:free()
    bb:blitFrom(grande, 0, 0, 0, 0, W, H)
    grande:free()
    bb:lightenRect(0, 0, W, H, 0.25)
end

local function comFundoDesfocado(menu)
    local pintar = menu.paintTo
    menu.paintTo = function(self, bb, x, y, ...)
        local W, H = bb:getWidth(), bb:getHeight()
        if self._lev_fundo then
            bb:blitFrom(self._lev_fundo, 0, 0, 0, 0, W, H) -- mesmo fundo, sem desfocar de novo
        else
            local ok = pcall(desfocar, bb)
            if ok then
                local c = Blitbuffer.new(W, H, Blitbuffer.TYPE_BB8)
                c:blitFrom(bb, 0, 0, 0, 0, W, H)
                self._lev_fundo = c
            end
        end
        return pintar(self, bb, x, y, ...)
    end
    local fechar = menu.onCloseWidget
    menu.onCloseWidget = function(self, ...)
        if self._lev_fundo then self._lev_fundo:free(); self._lev_fundo = nil end
        UIManager:setDirty("all", "ui") -- redesenha a tela de baixo sem o desfoque
        if fechar then return fechar(self, ...) end
    end
    -- a tela inteira atualiza junto com o menu
    UIManager:setDirty(nil, "ui", require("ui/geometry"):new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() })
end

local initOriginal = TouchMenu.init
function TouchMenu:init(...)
    self.last_index = 1 -- primeira aba = Ajustes rapidos
    initOriginal(self, ...)
    -- o ZenOS troca updateItems na classe; envolve a do proprio menu
    local atualizar = self.updateItems
    self.updateItems = function(menu, ...)
        local r = { atualizar(menu, ...) }
        pcall(subirStatus, menu)
        return unpack(r)
    end
    esconderBarra(self)
    pcall(comFundoDesfocado, self)
    -- borda do menu mais discreta: 1 px cinza escuro (antes: grossa e preta)
    local frame = self.menu_frame
    if frame then
        frame.bordersize = 1
        frame.color = require("ffi/blitbuffer").COLOR_DARK_GRAY
    end
    pcall(self.updateItems, self)
end

logger.info("Lev: menu rapido sem a barra de cima")
