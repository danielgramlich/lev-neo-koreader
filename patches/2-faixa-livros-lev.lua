-- Lev Neo (2026-11-06): faixa de livros do Inicio do ZenOS mais limpa.
-- * sem a barra de filtros (Recentes / lupa / Serie / setas): mais altura para as capas
-- * capas juntas (espacamento minimo) e alinhadas a esquerda
-- * v4: ate 6 livros, so uma pagina (sem pontinhos nem troca de pagina), sem o bloco "+"
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
        c.count = 5 -- o ZenOS limita a 5; a fileira passa a 6 pelo ajuste de medidas abaixo
        c._lev_seis = true
        c.show_page_indicator = false -- sem os pontinhos de pagina
        return c
    end

    -- dados da faixa so com a primeira pagina (sem "abas" de livros)
    local function dadosUmaPagina(data)
        if type(data) ~= "table" or data._lev_uma_pagina then return data end
        local proxy = setmetatable({ _lev_uma_pagina = true }, { __index = data, __newindex = data })
        for _, nome in ipairs({ "getStripItemsForPage", "getBooksForStripPage" }) do
            if type(data[nome]) == "function" then
                rawset(proxy, nome, function(_self, a, b, c, d, delta)
                    if delta and delta ~= 0 then return {}, false end
                    local livros = data[nome](data, a, b, c, d, 0)
                    return livros, false
                end)
            end
        end
        rawset(proxy, "getStripPageInfo", function() return nil end)
        return proxy
    end

    local function ctxAjustado(ctx)
        local novo = { module_cfg = ajustarCfg(ctx and ctx.module_cfg) }
        if ctx and ctx.data then novo.data = dadosUmaPagina(ctx.data) end
        return setmetatable(novo, { __index = ctx })
    end

    -- 6 capas na fileira: o ZenOS trava em 5 dentro de strip_layout_metrics; trocamos o
    -- resultado (count/per_row) so quando a configuracao vem marcada por este patch
    pcall(function()
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_common")
        local medidas, indice = userpatch.getUpValue(Strip.build_strip, "strip_layout_metrics")
        if type(medidas) == "function" then
            userpatch.replaceUpValue(Strip.build_strip, indice, function(largura, cfg, ...)
                local m = medidas(largura, cfg, ...)
                if type(m) == "table" and type(cfg) == "table" and cfg._lev_seis and not m.two_rows then
                    m.count, m.per_row = 6, 6
                end
                return m
            end)
        end
    end)

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
