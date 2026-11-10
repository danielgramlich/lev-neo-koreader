-- Lev Neo (2026-11-10): Biblioteca limpa. Esconde as pastas de sistema da raiz do Lev
-- (koreader, system, Digital Editions, Fonts, Imagens, Pictures) para so aparecerem livros
-- e a pasta "the news". Nada e apagado; as pastas continuam no aparelho.
-- Para desfazer: apague este arquivo (koreader/patches/2-biblioteca-lev.lua).
local FileChooser = require("ui/widget/filechooser")
local logger = require("logger")

local ESCONDER = { "^koreader$", "^system$", "^Digital Editions$", "^Fonts$", "^Imagens$", "^Pictures$" }
for _, padrao in ipairs(ESCONDER) do
    table.insert(FileChooser.exclude_dirs, padrao)
end
logger.info("Lev: biblioteca limpa (pastas de sistema escondidas)")
