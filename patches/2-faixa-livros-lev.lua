-- Lev Neo (2026-11-06): faixa de livros do Inicio do ZenOS mais limpa.
-- * sem a barra de filtros (Recentes / lupa / Serie / setas): mais altura para as capas
-- * capas juntas (espacamento minimo) e alinhadas a esquerda
-- * v3: 5 livros por pagina e um bloco "+" no fim, no formato das capas, que abre a Biblioteca
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
        c.count = 5 -- maximo do ZenOS numa fileira (as capas ficam do mesmo tamanho)
        return c
    end

    local function ctxAjustado(ctx)
        return setmetatable({ module_cfg = ajustarCfg(ctx and ctx.module_cfg) }, { __index = ctx })
    end

    -- bloco "+" no fim da fileira, no formato das capas: abre a Biblioteca
    local Blitbuffer = require("ffi/blitbuffer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local GestureRange = require("ui/gesturerange")
    local Geom = require("ui/geometry")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local UIManager = require("ui/uimanager")
    local okC, CoverCommon = pcall(require, "modules/filebrowser/patches/home/widgets/cover_common")
    local BORDA = (okC and CoverCommon and tonumber(CoverCommon.BORDER_SIZE)) or Screen:scaleBySize(1)
    local RAIO = Screen:scaleBySize(8)

    local function abrirBiblioteca()
        local abrir = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
        if type(abrir) == "function" then pcall(abrir, "books") end
    end

    local function blocoMais(w, h)
        local frame = FrameContainer:new{
            bordersize = BORDA, color = Blitbuffer.COLOR_BLACK, radius = RAIO,
            padding = 0, margin = 0, background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = math.max(1, w - 2 * BORDA), h = math.max(1, h - 2 * BORDA) },
                TextWidget:new{ text = "+", face = Font:getFace("cfont", 40), fgcolor = Blitbuffer.COLOR_BLACK },
            },
        }
        local toque = InputContainer:new{
            dimen = Geom:new{ w = w, h = h },
            ges_events = {
                TapLevMais = { GestureRange:new{ ges = "tap", range = Geom:new{
                    x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } } },
            },
            frame,
        }
        toque.onTapLevMais = function(self, _arg, ges)
            if not (self.dimen and ges and ges.pos and self.dimen:contains(ges.pos)) then return false end
            local M = rawget(_G, "__LEV_MODAL")
            if M and M.durante then M.durante("Loading…", abrirBiblioteca) else UIManager:nextTick(abrirBiblioteca) end
            return true
        end
        return toque
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
            -- "+" depois do ultimo livro (uma vez por fileira; fileiras refeitas ganham de novo)
            if not fileira._lev_mais and #fileira > 0 and type(fileira[1].getSize) == "function" then
                local tam = fileira[1]:getSize()
                if tam and tam.w and tam.w > 0 then
                    table.insert(fileira, HorizontalSpan:new{ width = ESPACO })
                    table.insert(fileira, blocoMais(tam.w, tam.h))
                    fileira._lev_mais = true
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
