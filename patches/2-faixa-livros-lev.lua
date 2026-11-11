-- Lev Neo (2026-11-06): faixa de livros do Inicio do ZenOS mais limpa.
-- * sem a barra de filtros (Recentes / lupa / Serie / setas): mais altura para as capas
-- * capas juntas (espacamento minimo) e alinhadas a esquerda
-- O ZenOS regrava a configuracao da faixa ao iniciar, entao o ajuste e feito na hora
-- de desenhar (envolvendo o componente "strip" do registro do Inicio).
-- Para desfazer: apague este arquivo (koreader/patches/2-faixa-livros-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")

userpatch.registerPatchPluginFunc("zenos", function()
    local ok, Registry = pcall(require, "modules/filebrowser/patches/home/components/registry")
    local comp = ok and Registry and Registry.get and Registry.get("strip")
    if not comp or comp._lev_ajustado then
        if not comp then logger.warn("Lev faixa: componente strip nao encontrado") end
        return
    end
    comp._lev_ajustado = true

    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local Screen = require("device").screen
    local ESPACO = Screen:scaleBySize(10)

    -- copia da configuracao com filtros desligados e capas juntas
    local function ajustarCfg(cfg)
        local c = {}
        for k, v in pairs(type(cfg) == "table" and cfg or {}) do c[k] = v end
        local controles = {}
        for k, v in pairs(type(c.controls) == "table" and c.controls or {}) do controles[k] = v end
        controles.enabled = false
        c.controls = controles
        c.center_books = true -- espacamento minimo entre as capas
        return c
    end

    local function ctxAjustado(ctx)
        return setmetatable({ module_cfg = ajustarCfg(ctx and ctx.module_cfg) }, { __index = ctx })
    end

    -- a fileira de capas vem num CenterContainer; trocamos por LeftContainer
    local trocas = 0
    local function alinharEsquerda(w, prof)
        if type(w) ~= "table" or prof > 30 then return end
        local mt = getmetatable(w)
        if (mt == CenterContainer or mt == LeftContainer) and type(w[1]) == "table"
                and getmetatable(w[1]) == HorizontalGroup and w.dimen and w.dimen.w
                and w.dimen.w > Screen:getWidth() * 0.6 then
            -- fileira de capas: a esquerda e com espacamento curto (qualquer numero de livros)
            local mudou = mt ~= LeftContainer
            setmetatable(w, LeftContainer)
            local fileira = w[1]
            for i = 1, #fileira do
                if getmetatable(fileira[i]) == HorizontalSpan and fileira[i].width ~= ESPACO then
                    fileira[i].width = ESPACO
                    mudou = true
                end
            end
            if mudou then
                if fileira.resetLayout then fileira:resetLayout() end
                trocas = trocas + 1
            end
        end
        for i = 1, #w do alinharEsquerda(w[i], prof + 1) end
    end

    -- v2: a faixa guarda paginas prontas e as refaz por dentro (capa que termina de
    -- carregar, troca de pagina) sem passar por build. Por isso o ajuste roda tambem a
    -- cada desenho da faixa, antes de pintar.
    local build = comp.build
    comp.build = function(ctx, ...)
        local w = build(ctxAjustado(ctx), ...)
        trocas = 0
        local ok, err = pcall(alinharEsquerda, w, 0)
        logger.dbg("Lev faixa: fileiras alinhadas a esquerda:", trocas, ok and "" or err)
        if type(w) == "table" and type(w.paintTo) == "function" and not w._lev_pinta then
            w._lev_pinta = true
            local pintar = w.paintTo
            w.paintTo = function(self, bb, x, y, ...)
                trocas = 0
                pcall(alinharEsquerda, self, 0)
                if trocas > 0 then logger.dbg("Lev faixa: realinhada ao desenhar:", trocas) end
                return pintar(self, bb, x, y, ...)
            end
        end
        return w
    end
    if type(comp.preferredHeight) == "function" then
        local altura = comp.preferredHeight
        comp.preferredHeight = function(ctx, ...)
            return altura(ctxAjustado(ctx), ...)
        end
    end
    logger.info("Lev: faixa de livros sem filtros e alinhada a esquerda")
end)
