-- Lev Neo (2026-11-09): renomeia os livros para o padrao "Titulo - Autor"
-- (so a primeira letra do titulo maiuscula, mais nomes proprios; autor completo).
-- Usa o renomear do proprio KOReader (FileManager:renameFile), que leva junto a pasta
-- .sdr (progresso, marcacoes, capa personalizada), o historico e as colecoes.
-- Roda uma vez ao iniciar; livros ja renomeados (ou ausentes) sao ignorados.
-- Para desfazer: renomeie de volta pela Biblioteca (segurar no livro > Renomear).
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local PASTA = "/mnt/fat"

-- nome atual (sem extensao) -> nome novo (sem extensao)
local NOMES = {
    -- { "current file name (no extension)", "New title - Author Name" },
    -- { "1984 - GEORGE ORWELL", "1984 - George Orwell" },
}

-- chave tolerante a acentos compostos/decompostos (mesma ideia do 2-capas-lev.lua)
local function chave(nome)
    return (nome:lower():gsub("[^%w]", ""):gsub("[aeioucn]", ""))
end

local function renomear()
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if not fm or not fm.renameFile then return nil, "biblioteca nao carregada" end
    local atuais = {}
    for nome in lfs.dir(PASTA) do
        local base, ext = nome:match("^(.+)%.([%w]+)$")
        if base and not nome:match("^%.") and lfs.attributes(PASTA .. "/" .. nome, "mode") == "file" then
            atuais[chave(base)] = { nome = nome, base = base, ext = ext }
        end
    end
    local feitos = 0
    for _, par in ipairs(NOMES) do
        local atual = atuais[chave(par[1])]
        local novo = par[2] .. "." .. (atual and atual.ext or "")
        if atual and atual.base ~= par[2] and lfs.attributes(PASTA .. "/" .. novo, "mode") == nil then
            local de = PASTA .. "/" .. atual.nome
            local ok, err = pcall(fm.renameFile, fm, de, novo, true)
            if ok and lfs.attributes(PASTA .. "/" .. novo, "mode") == "file" then
                feitos = feitos + 1
                logger.info("Lev renomear:", atual.nome, "->", novo)
            else
                logger.warn("Lev renomear: falhou", atual.nome, err)
            end
        end
    end
    return feitos
end

UIManager:scheduleIn(12, function()
    if G_reader_settings:isTrue("lev_renomeado_v1") then return end
    local ok, n, err = pcall(renomear)
    if ok and n then
        logger.info("Lev renomear: livros renomeados:", n)
        G_reader_settings:saveSetting("lev_renomeado_v1", true)
        G_reader_settings:flush()
    else
        logger.warn("Lev renomear: nao rodou:", ok and err or n)
    end
end)
