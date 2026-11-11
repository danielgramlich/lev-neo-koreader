-- Lev Neo (2026-11-11): menu de acesso rapido sem a barra de cima.
-- Esconde a barra de abas do menu (icones de ajustes rapidos, apps, engrenagem e Inicio):
-- ela deixa de ser desenhada e nao ocupa espaco. O menu sempre abre nos Ajustes rapidos.
-- Inicio, Biblioteca e Ajustes continuam na barra de baixo do Lev.
-- Tambem sobe 2 px a linha de hora, Wi-Fi e bateria.
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
    pcall(self.updateItems, self)
end

logger.info("Lev: menu rapido sem a barra de cima")
