-- Lev Neo (2026-11-11): menu de acesso rapido sem a barra de cima.
-- Esconde a barra de abas do menu (icones de ajustes rapidos, apps, engrenagem e Inicio):
-- ela deixa de ser desenhada e nao ocupa espaco. O menu sempre abre nos Ajustes rapidos.
-- Inicio, Biblioteca e Ajustes continuam na barra de baixo do Lev.
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

local initOriginal = TouchMenu.init
function TouchMenu:init(...)
    self.last_index = 1 -- primeira aba = Ajustes rapidos
    initOriginal(self, ...)
    if esconderBarra(self) then pcall(self.updateItems, self) end
end

logger.info("Lev: menu rapido sem a barra de cima")
