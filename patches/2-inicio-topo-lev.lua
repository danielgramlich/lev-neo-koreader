-- Lev Neo (2026-11-11): Inicio 13 px mais baixo.
-- A tela do Lev tem uma linha morta perto do topo; descer o Inicio 13 px tira o texto de
-- cima dela.
-- Como: quando o ZenOS monta o corpo do Inicio na tela (StandalonePage.mount_body), o
-- bloco inteiro ganha 10 px em cima. Tudo desce junto, entao espacos, faixas e areas de
-- toque continuam iguais entre si. So vale para o Inicio (outras paginas nao mudam).
-- Para desfazer: apague este arquivo (koreader/patches/2-inicio-topo-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")

local DESCER = 13

userpatch.registerPatchPluginFunc("zenos", function()
    local ok, Pagina = pcall(require, "modules/filebrowser/patches/standalone_page")
    if not ok or type(Pagina) ~= "table" or type(Pagina.mount_body) ~= "function" then
        logger.warn("Lev inicio: montagem de pagina do ZenOS nao encontrada")
        return
    end
    if Pagina._lev_topo then return end
    Pagina._lev_topo = true
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local original = Pagina.mount_body
    Pagina.mount_body = function(menu, conteudo, ...)
        -- so o Inicio marca _zen_home_page_padding no menu antes de montar
        if type(menu) == "table" and menu._zen_home_page_padding ~= nil and type(conteudo) == "table" then
            conteudo = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = DESCER }, conteudo }
        end
        return original(menu, conteudo, ...)
    end
    logger.info("Lev: Inicio", DESCER, "px mais baixo")
end)
