-- Lev Neo (2026-11-06): rodape da leitura no estilo Kindle.
-- Troca o "icone + 6m" do tempo restante no capitulo por
-- "6 min restantes no capitulo".
-- Para desfazer: apague este arquivo (koreader/patches/2-rodape-lev.lua).
local userpatch = require("userpatch")
local ReaderFooter = require("apps/reader/modules/readerfooter")
local logger = require("logger")

local mapa = userpatch.getUpValue(ReaderFooter.updateFooterTextGenerator, "footerTextGeneratorMap")
if type(mapa) ~= "table" then
    logger.warn("Lev: rodape nao encontrado, patch ignorado")
    return
end

local function legivel(t)
    if not t or t == "" then return nil end
    t = t:gsub("(%d+)h%s*0*(%d+)m", "%1 h %2 min")
    t = t:gsub("^(%d+)m$", "%1 min")
    t = t:gsub("^(%d+)h$", "%1 h")
    return t
end

mapa.chapter_time_to_read = function(footer)
    local left = footer.ui.toc:getChapterPagesLeft(footer.pageno, true)
        or footer.ui.document:getTotalPagesLeft(footer.pageno)
    if left and left <= 0 then return "End of chapter" end
    local t = footer.ui.statistics and legivel(footer.ui.statistics:getTimeForPages(left))
    if not t then return "" end
    return t .. " left in chapter"
end

logger.info("Lev: rodape estilo Kindle ativo")
