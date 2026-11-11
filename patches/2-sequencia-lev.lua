-- Lev Neo (2026-11-11): icone do "Day streak" no Inicio.
-- Troca a chama preta cheia do ZenOS por uma chama so de contorno, no traco fino dos
-- outros icones do Lev (koreader/icons/lev_sequencia.svg).
-- Para desfazer: apague este arquivo (koreader/patches/2-sequencia-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")

local ICONE = "/mnt/fat/koreader/icons/lev_sequencia.svg"

userpatch.registerPatchPluginFunc("zenos", function()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(ICONE, "mode") ~= "file" then
        logger.warn("Lev sequencia: icone nao encontrado:", ICONE)
        return
    end
    local ok, Packs = pcall(require, "common/icon_packs")
    if ok and type(Packs) == "table" and type(Packs.resolve) == "function" and not Packs._lev_chama then
        Packs._lev_chama = true
        local resolver = Packs.resolve
        Packs.resolve = function(nome, ...)
            if nome == "flame" then return ICONE end
            return resolver(nome, ...)
        end
    end
    -- o widget de estatisticas guarda o caminho do icone numa tabela interna
    -- (stat_icon_paths) resolvida quando o ZenOS carrega; troca a entrada "streak" la
    local function acharTabela(fn, prof, vistos)
        if type(fn) ~= "function" or prof > 3 or vistos[fn] then return nil end
        vistos[fn] = true
        local i = 1
        while true do
            local nome, valor = debug.getupvalue(fn, i)
            if not nome then break end
            if nome == "stat_icon_paths" and type(valor) == "table" then return valor end
            if type(valor) == "function" then
                local t = acharTabela(valor, prof + 1, vistos)
                if t then return t end
            end
            i = i + 1
        end
    end
    local okR, Registry = pcall(require, "modules/filebrowser/patches/home/components/registry")
    local comp = okR and Registry and Registry.get and Registry.get("stats_triplet")
    local tabela = comp and acharTabela(comp.build, 0, {})
    if tabela then
        tabela.streak = ICONE
    else
        logger.warn("Lev sequencia: tabela de icones das estatisticas nao encontrada")
    end
    logger.info("Lev: icone de sequencia em traco fino")
end)
