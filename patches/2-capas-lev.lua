-- Lev Neo (2026-11-09): capas dos livros em alta qualidade, no tamanho exato da tela
-- (758 x 1024), para a tela de descanso ocupar 100% sem distorcer.
-- Coloque PNGs em /mnt/fat/koreader/capas_lev/ com o mesmo nome do livro (sem extensao),
-- ex.: "1984 - George Orwell.png" para "/mnt/fat/1984 - George Orwell.epub".
-- Ao iniciar, cada capa vira a capa personalizada do livro (DocSettings, a mesma usada
-- pelo the news), o cache de capas do ZenOS e limpo e o PNG vai para capas_lev/aplicadas.
-- Para desfazer uma capa: Biblioteca > segurar no livro > capa > restaurar.
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PASTA_CAPAS = "/mnt/fat/koreader/capas_lev"
local PASTA_LIVROS = "/mnt/fat"
local EXTENSOES = { epub = true, pdf = true, mobi = true, azw3 = true, fb2 = true, cbz = true }

-- chave tolerante a diferencas de acentuacao/normalizacao Unicode no nome
-- (acentos podem vir compostos "õ" ou decompostos "o"+"~": tiramos tudo que nao e ASCII
-- e tambem as letras que podem levar acento, para as duas formas darem a mesma chave)
local function chave(nome)
    return (nome:lower():gsub("[^%w]", ""):gsub("[aeioucn]", ""))
end

local function aplicar()
    if lfs.attributes(PASTA_CAPAS, "mode") ~= "directory" then return 0 end
    local livros = {}
    for nome in lfs.dir(PASTA_LIVROS) do
        local base, ext = nome:match("^(.+)%.([%w]+)$")
        if base and not nome:match("^%.") and EXTENSOES[ext:lower()] then -- ignora ocultos (._ do macOS)
            livros[chave(base)] = PASTA_LIVROS .. "/" .. nome
        end
    end
    local DocSettings = require("docsettings")
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    local feitas = 0
    lfs.mkdir(PASTA_CAPAS .. "/aplicadas")
    for arq in lfs.dir(PASTA_CAPAS) do
        local base = arq:match("^(.+)%.png$")
        if base and not base:match("^_") and not arq:match("^%.") then
            local capa = PASTA_CAPAS .. "/" .. arq
            local livro = livros[chave(base)]
            if livro then
                local ok, err = pcall(function() DocSettings:flushCustomCover(livro, capa) end)
                if ok then
                    if ok_bim and BookInfoManager and BookInfoManager.deleteBookInfo then
                        pcall(BookInfoManager.deleteBookInfo, BookInfoManager, livro)
                    end
                    os.rename(capa, PASTA_CAPAS .. "/aplicadas/" .. arq)
                    feitas = feitas + 1
                    logger.info("Lev capas: aplicada em", livro)
                else
                    logger.warn("Lev capas: erro em", livro, err)
                end
            else
                logger.warn("Lev capas: livro nao encontrado para", arq)
            end
        end
    end
    return feitas
end

-- tela de descanso como no Kindle: amplia a capa ate cobrir a tela e corta o que sobra
-- (so na hora de mostrar; na Biblioteca a capa continua inteira)
G_reader_settings:makeTrue("screensaver_images_crop_to_fit")
G_reader_settings:makeFalse("screensaver_stretch_images")

UIManager:scheduleIn(8, function()
    local ok, n = pcall(aplicar)
    if ok and n > 0 then
        logger.info("Lev capas: capas aplicadas:", n)
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance and FileManager.instance.onRefresh then
            pcall(FileManager.instance.onRefresh, FileManager.instance)
        end
    elseif not ok then
        logger.warn("Lev capas: erro:", n)
    end
end)
