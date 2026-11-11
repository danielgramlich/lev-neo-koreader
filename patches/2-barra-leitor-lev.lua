-- Lev Neo (2026-11-06): barra inferior do ZenOS fixa tambem durante a leitura do the news
-- (so nas edicoes em /mnt/fat/the news; nos livros a leitura continua em tela cheia).
-- O ZenOS so mostra a barra na biblioteca; aqui desenhamos uma igual (mesmas abas,
-- icones, fonte, tamanhos e espacamento, lidos da configuracao do ZenOS) no rodape
-- do leitor. O rodape ("X min restantes...") e o texto sobem pela altura da barra.
-- Toques na barra: Biblioteca e Inicio fecham o livro como o ZenOS faz; the news,
-- Spotify e Ajustes chamam os mesmos metodos das abas personalizadas.
-- Para desfazer: apague este arquivo (koreader/patches/2-barra-leitor-lev.lua).
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local ReaderUI = require("apps/reader/readerui")
local ReaderView = require("apps/reader/modules/readerview")
local ReaderFooter = require("apps/reader/modules/readerfooter")

local PASTA_NEWS = "/mnt/fat/the news/"

local function zen() return rawget(_G, "__ZEN_UI_PLUGIN") end

-- configuracao da barra: a do ZenOS carregado; se ainda nao estiver (o leitor abre
-- antes do plugin), le direto do arquivo settings/ZenOS/config.lua
local function cfgBarra()
    local z = zen()
    local nb = z and type(z.config) == "table" and type(z.config.navbar) == "table" and z.config.navbar
    if nb and type(nb.custom_tabs) == "table" and type(nb.tab_order) == "table" then return nb end
    local DataStorage = require("datastorage")
    local ok, t = pcall(dofile, DataStorage:getSettingsDir() .. "/ZenOS/config.lua")
    if ok and type(t) == "table" and type(t.navbar) == "table" then return t.navbar end
    return nb or {}
end

local function fonte(tamanho)
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, face = pcall(lf.getFace, tamanho)
        if ok2 and face then return face end
    end
    return Font:getFace("cfont", tamanho)
end

-- abas visiveis, na ordem do ZenOS
local function abas()
    local cfg = cfgBarra()
    local lista = {}
    local custom = {}
    for _, ct in ipairs(cfg.custom_tabs or {}) do
        if type(ct) == "table" and ct.id then custom[ct.id] = ct end
    end
    local mostrar = type(cfg.show_tabs) == "table" and cfg.show_tabs or {}
    for _, id in ipairs(cfg.tab_order or { "books", "home" }) do
        if mostrar[id] ~= false then
            if id == "books" then
                table.insert(lista, { id = id, icon = "library",
                    label = (cfg.books_label and cfg.books_label ~= "") and cfg.books_label or "Library" })
            elseif id == "home" then
                table.insert(lista, { id = id, icon = "home",
                    label = (cfg.home_label and cfg.home_label ~= "") and cfg.home_label or "Home" })
            elseif custom[id] and mostrar[id] == true then
                local ct = custom[id]
                table.insert(lista, { id = id, icon = ct.icon or "zen_ui", label = ct.label or ct.plugin_title or id })
            end
        end
        if #lista >= 7 then break end
    end
    return lista
end

-- ---------- desenho (replica do createNavBar do ZenOS) ----------
local barra = { widget = nil, altura = nil, centros = nil, ativa = nil, largura = nil }

local function montarBarra(ativa)
    local cfg = cfgBarra()
    local W = Screen:getWidth()
    local icone_px = Screen:scaleBySize(tonumber(cfg.icon_size) or 34)
    local v_pad = Screen:scaleBySize(4)
    local h_pad = Screen:scaleBySize(10)
    local linha_px = Screen:scaleBySize(2)
    local mostrar_rotulo = cfg.show_labels ~= false
    local lista = abas()
    local n = math.max(1, #lista)
    local interno = W - 2 * h_pad
    local rotulo_max = math.floor(interno / n) - Screen:scaleBySize(4)

    -- um tamanho de fonte que caiba em todos os rotulos
    local base = tonumber(cfg.label_size) or 20
    local face
    for _, tam in ipairs({ base, base - 2, base - 4, base - 6 }) do
        face = fonte(math.max(8, tam))
        local cabe = true
        for _, t in ipairs(lista) do
            local p = TextWidget:new{ text = t.label, face = face }
            if p:getSize().w > rotulo_max then cabe = false end
            p:free()
            if not cabe then break end
        end
        if cabe then break end
    end

    local itens, total = {}, 0
    for i, t in ipairs(lista) do
        local filhos = { align = "center" }
        table.insert(filhos, IconWidget:new{ icon = t.icon, width = icone_px, height = icone_px })
        local rotulo
        if mostrar_rotulo then
            rotulo = TextWidget:new{ text = t.label, face = face, max_width = rotulo_max, fgcolor = Blitbuffer.COLOR_BLACK }
            table.insert(filhos, rotulo)
        end
        if t.id == ativa and cfg.active_tab_underline ~= false then
            local w = rotulo and rotulo:getSize().w or icone_px
            local linha = Widget:new{ dimen = Geom:new{ w = w, h = linha_px } }
            function linha:paintTo(bb, x, y) bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_BLACK) end
            table.insert(filhos, linha)
        else
            table.insert(filhos, VerticalSpan:new{ width = linha_px })
        end
        local aba = VerticalGroup:new{ align = "center",
            VerticalSpan:new{ width = v_pad }, VerticalGroup:new(filhos), VerticalSpan:new{ width = v_pad } }
        itens[i] = aba
        total = total + aba:getSize().w
    end

    local resto = interno - total
    local gap = math.max(0, math.floor(resto / (n + 1)))
    local extra = resto - gap * (n + 1)
    local linha = HorizontalGroup:new{ align = "center", HorizontalSpan:new{ width = h_pad } }
    local centros, x = {}, h_pad
    for i, aba in ipairs(itens) do
        local g = gap + (i <= extra and 1 or 0)
        table.insert(linha, HorizontalSpan:new{ width = g })
        x = x + g
        local w = aba:getSize().w
        centros[i] = { x = x + w / 2, id = lista[i].id }
        table.insert(linha, aba)
        x = x + w
    end
    table.insert(linha, HorizontalSpan:new{ width = gap + h_pad })

    logger.dbg("Lev barra leitor: abas", #lista, "altura", linha:getSize().h)
    barra.widget = linha
    barra.altura = linha:getSize().h
    barra.centros = centros
    barra.ativa = ativa
    barra.largura = W
    -- as telas do ZenOS/Spotify usam esta altura para nao cobrir a barra
    if not tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT") <= 0 then
        _G.__ZEN_UI_NAVBAR_HEIGHT = barra.altura
    end
    return linha
end

-- a barra so aparece nas edicoes do the news
local function comBarra(ui)
    local arq = ui and ui.document and ui.document.file
    return arq ~= nil and arq:sub(1, #PASTA_NEWS) == PASTA_NEWS
end

local function abaAtiva()
    local ui = ReaderUI.instance
    local arq = ui and ui.document and ui.document.file
    if arq and arq:sub(1, #PASTA_NEWS) == PASTA_NEWS then return "lev_thenews" end
    return nil
end

local function alturaBarra()
    if not barra.altura or barra.largura ~= Screen:getWidth() then
        local ok, err = pcall(montarBarra, abaAtiva())
        if not ok then
            logger.warn("Lev barra leitor: erro ao montar:", err)
            return 0
        end
    end
    return barra.altura or 0
end

-- ---------- acoes das abas ----------
local function acao(id)
    local ui = ReaderUI.instance
    local z = zen()
    if not ui then return end
    if id == "books" or id == "home" then
        local ok, nav = pcall(require, "common/library_navigation")
        if ok and nav and nav.showFromReader and z then
            if id == "home" then
                nav.showFromReader(ui, z, { open_home = true })
            else
                nav.showFromReader(ui, z, { target_tab = "books" })
            end
        else
            ui:onClose()
            ui:showFileManager(ui.document and ui.document.file)
        end
        return
    end
    -- abas personalizadas do tipo plugin ({key, method})
    for _, ct in ipairs(cfgBarra().custom_tabs or {}) do
        if ct.id == id and ct.type == "plugin" and type(ct.plugin) == "table" then
            local inst
            if ct.plugin.key == "zenos" then
                inst = z
            else
                local ok_pl, PluginLoader = pcall(require, "pluginloader")
                inst = ui[ct.plugin.key]
                    or (ok_pl and PluginLoader.getPluginInstance and PluginLoader:getPluginInstance(ct.plugin.key))
            end
            local metodo = inst and inst[ct.plugin.method]
            if type(metodo) == "function" then
                local ok, err = pcall(metodo, inst)
                if not ok then logger.warn("Lev barra leitor: erro na aba", id, err) end
            else
                logger.warn("Lev barra leitor: acao nao encontrada para", id)
            end
            return
        end
    end
end

local function abaNoPonto(x)
    local melhor, dist
    for _, c in ipairs(barra.centros or {}) do
        local d = math.abs(x - c.x)
        if not dist or d < dist then melhor, dist = c.id, d end
    end
    return melhor
end

-- ---------- rodape: reserva o espaco da barra ----------
local updateOriginal = ReaderFooter.updateFooterContainer
function ReaderFooter:updateFooterContainer(...)
    self.bottom_padding = Screen:scaleBySize(self.settings.container_bottom_padding or 1)
        + (comBarra(self.ui) and alturaBarra() or 0)
    return updateOriginal(self, ...)
end

-- ---------- margem de baixo: o texto termina acima do rodape + barra ----------
-- Com "Sobrepor barra de status" (reclaim_height) o leitor nao reserva espaco para o
-- rodape; no the news reservamos rodape + barra, senao o texto passa por baixo dela.
local ReaderTypeset = require("apps/reader/modules/readertypeset")
local margensOriginal = ReaderTypeset.onSetPageMargins
function ReaderTypeset:onSetPageMargins(margins, ...)
    local footer = self.view and self.view.footer
    if not (comBarra(self.ui) and footer and footer.reclaim_height and self.ui.document) then
        return margensOriginal(self, margins, ...)
    end
    local doc = self.ui.document
    local tinha = rawget(doc, "setPageMargins")
    local setOriginal = doc.setPageMargins
    doc.setPageMargins = function(d, l, t, r, b)
        return setOriginal(d, l, t, r, b + footer:getHeight())
    end
    local ok, err = pcall(margensOriginal, self, margins, ...)
    doc.setPageMargins = tinha -- volta ao metodo da classe
    if not ok then logger.warn("Lev barra leitor: erro nas margens:", err) end
end

-- ---------- desenho por cima da pagina ----------
local paintOriginal = ReaderView.paintTo
function ReaderView:paintTo(bb, x, y)
    paintOriginal(self, bb, x, y)
    if not comBarra(self.ui) then return end
    if not barra.widget or barra.ativa ~= abaAtiva() or barra.largura ~= Screen:getWidth() then
        local ok = pcall(montarBarra, abaAtiva())
        if not ok then return end
    end
    local h = barra.altura
    local topo = y + self.dimen.h - h
    bb:paintRect(x, topo, self.dimen.w, h, Blitbuffer.COLOR_WHITE)
    barra.widget:paintTo(bb, x, topo)
end

-- ---------- toque na barra (tem prioridade sobre as zonas do leitor) ----------
local initOriginal = ReaderUI.init
function ReaderUI:init(...)
    initOriginal(self, ...)
    local ui = self
    UIManager:nextTick(function()
        if ui ~= ReaderUI.instance or not ui.registerTouchZones then return end
        if not comBarra(ui) then return end
        local H = Screen:getHeight()
        -- remonta com a configuracao do ZenOS ja carregada
        barra.widget, barra.altura = nil, nil
        local h = alturaBarra()
        if h <= 0 then return end
        local outras = {}
        for _, z in ipairs(ui._ordered_touch_zones or {}) do
            if z.def and z.def.id then table.insert(outras, z.def.id) end
        end
        local function zona(id, ges)
            return {
                id = id, ges = ges,
                screen_zone = { ratio_x = 0, ratio_y = (H - h) / H, ratio_w = 1, ratio_h = h / H },
                overrides = outras,
                handler = function(g)
                    if ges == "tap" then
                        local aba = abaNoPonto(g.pos.x)
                        if aba then UIManager:nextTick(function() acao(aba) end) end
                    end
                    return true
                end,
            }
        end
        ui:registerTouchZones({ zona("lev_barra_toque", "tap"), zona("lev_barra_segurar", "hold") })
        -- o rodape ja foi montado antes: aplica o espaco da barra e recalcula as margens
        if ui.view and ui.view.footer then
            ui.view.footer:updateFooterContainer()
            ui.view.footer:resetLayout(true)
        end
        if ui.typeset and ui.typeset.unscaled_margins then
            local Event = require("ui/event")
            ui:handleEvent(Event:new("SetPageMargins", ui.typeset.unscaled_margins))
        end
        UIManager:setDirty(ui, "ui")
    end)
end

logger.info("Lev: barra inferior fixa no leitor ativa")

-- Usado por outras telas do Lev (Ajustes, Spotify) que ficam acima da barra do ZenOS:
-- a barra do Inicio do ZenOS sempre sublinha "Home", entao essas telas pintam esta copia
-- por cima dela, com a propria aba sublinhada.
_G.__LEV_BARRA = {
    pintar = function(bb, ativa)
        if not (barra.widget and barra.ativa == ativa and barra.largura == Screen:getWidth()) then
            montarBarra(ativa)
        end
        local W, H = Screen:getWidth(), Screen:getHeight()
        local zen_h = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
        local cobrir = math.max(zen_h, barra.altura or 0)
        bb:paintRect(0, H - cobrir, W, cobrir, Blitbuffer.COLOR_WHITE)
        barra.widget:paintTo(bb, 0, H - barra.altura)
        return cobrir
    end,
}
