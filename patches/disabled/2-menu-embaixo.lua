-- Lev Neo (2026-11-06): menu principal ancorado no RODAPE da tela.
-- O touch do Lev nao funciona direito na faixa de cima (defeito do sensor),
-- entao o menu passa a abrir e a ser desenhado embaixo.
-- Para desfazer: apague este arquivo (koreader/patches/2-menu-embaixo.lua).
local BottomContainer = require("ui/widget/container/bottomcontainer")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen

local function ancorarEmbaixo(Modulo)
    local showOriginal = Modulo.onShowMenu
    Modulo.onShowMenu = function(self, tab_index, do_not_show)
        showOriginal(self, tab_index, true) -- monta o menu sem mostrar
        local main_menu = self.menu_container and self.menu_container[1]
        if not main_menu then return true end
        local container = BottomContainer:new{
            dimen = Screen:getSize(),
            main_menu,
        }
        main_menu.show_parent = container
        self.menu_container = container
        if not do_not_show then
            UIManager:show(container)
        end
        return true
    end
    -- deslizar para CIMA a partir do rodape tambem abre o menu
    local swipeOriginal = Modulo.onSwipeShowMenu
    Modulo.onSwipeShowMenu = function(self, ges)
        if ges and ges.direction == "north" then
            ges = { direction = "south", pos = ges.pos }
        end
        return swipeOriginal(self, ges)
    end
end

ancorarEmbaixo(require("apps/filemanager/filemanagermenu"))
ancorarEmbaixo(require("apps/reader/modules/readermenu"))
