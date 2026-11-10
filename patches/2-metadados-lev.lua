-- Lev Neo (2026-11-09): titulo e autor de cada livro iguais ao nome do arquivo
-- ("Titulo - Autor"), em vez do que vem gravado no epub/pdf (ex.: "(tcon-2)",
-- "Clive Staples Lewis"). Grava como metadados personalizados do KOReader (o mesmo
-- mecanismo do the news); o arquivo do livro nao e alterado.
-- Roda uma vez (marca lev_metadados_v2; v2 inclui descricoes limpas). Para refazer, apague a marca em settings.reader.lua.
-- Para desfazer num livro: Biblioteca > segurar no livro > Informacoes > restaurar.
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PASTA = "/mnt/fat"
local EXTENSOES = { epub = true, pdf = true, mobi = true, azw3 = true, fb2 = true, cbz = true }

-- v2: descricoes limpas (texto puro, pontuacao do cp1252 corrigida, corte so entre palavras),
-- geradas no Mac a partir do proprio epub; "" = esconder descricao inutil
local DESCRICOES = {
    -- Fill in with your own clean descriptions, keyed by the file name without extension:
    -- [ [==[Title - Author]==] ] = [==[Short description...]==],
    -- [ [==[Another title - Author]==] ] = [==[]==],  -- "" hides a useless description
}

local function aplicar()
    local DocSettings = require("docsettings")
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    local feitos = 0
    for nome in lfs.dir(PASTA) do
        local base, ext = nome:match("^(.+)%.([%w]+)$")
        if base and not nome:match("^%.") and EXTENSOES[ext:lower()] then
            local titulo, autor = base:match("^(.-)%s+%-%s+([^%-]+)$")
            if titulo and autor then
                local caminho = PASTA .. "/" .. nome
                local arq = DocSettings:findCustomMetadataFile(caminho)
                local custom = DocSettings.openSettingsFile(arq)
                local doc_props = custom:readSetting("doc_props")
                if type(doc_props) ~= "table" then
                    doc_props = {}
                    local info = ok_bim and BookInfoManager and BookInfoManager.getBookInfo
                        and BookInfoManager:getBookInfo(caminho)
                    if type(info) == "table" then
                        doc_props.title, doc_props.authors = info.title, info.authors
                        doc_props.series, doc_props.language = info.series, info.language
                        doc_props.description = info.description
                    end
                    doc_props.title = doc_props.title or titulo
                    doc_props.authors = doc_props.authors or autor
                end
                local props = custom:readSetting("custom_props") or {}
                props.title, props.authors = titulo, autor
                if DESCRICOES[base] ~= nil then props.description = DESCRICOES[base] end
                custom.data.doc_props = doc_props
                custom.data.custom_props = props
                custom:flushCustomMetadata(caminho)
                if ok_bim and BookInfoManager and BookInfoManager.deleteBookInfo then
                    pcall(BookInfoManager.deleteBookInfo, BookInfoManager, caminho)
                end
                feitos = feitos + 1
            end
        end
    end
    return feitos
end

UIManager:scheduleIn(15, function()
    if G_reader_settings:isTrue("lev_metadados_v2") then return end
    local ok, n = pcall(aplicar)
    if ok then
        logger.info("Lev metadados: livros atualizados:", n)
        G_reader_settings:saveSetting("lev_metadados_v2", true)
        G_reader_settings:flush()
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance and FileManager.instance.onRefresh then
            pcall(FileManager.instance.onRefresh, FileManager.instance)
        end
    else
        logger.warn("Lev metadados: erro:", n)
    end
end)
