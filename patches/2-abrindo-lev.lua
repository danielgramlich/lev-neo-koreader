-- Lev Neo (2026-11-10, v4): modal de carregamento padrao, no centro da tela (sem desfoque).
-- Toda acao que demora mostra o mesmo modal (pilula branca, borda fina, sombra suave,
-- tres pontinhos + texto), para nenhum toque parecer ignorado:
--   * abrir um livro / edicao ............. "Opening…" (substitui a faixa preta do ZenOS)
--   * sair do livro para o Inicio/Biblioteca "Loading…"
--   * outras telas (Spotify, Word of the day...) chamam _G.__LEV_MODAL
--   * a barrinha de progresso do motor de EPUB (canto superior esquerdo) vira o mesmo modal
-- API: local m = _G.__LEV_MODAL.mostrar("Loading…")   -- desenha na hora
--      _G.__LEV_MODAL.fechar(m)                         -- ou fecha sozinho em 12 s
-- Para desfazer: apague este arquivo (koreader/patches/2-abrindo-lev.lua).
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local userpatch = require("userpatch")
local logger = require("logger")
local Screen = Device.screen


local function fonte(tamanho)
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, face = pcall(lf.getFace, tamanho)
        if ok2 and face then return face end
    end
    return Font:getFace("cfont", tamanho)
end

local TAM = 17

-- desenho da pilula (usado pelo modal e pelo aviso do ZenOS)
local geometria -- abaixo
local function desenharPilula(bb, texto)
    local g = geometria(texto)
    local x, y = g.x, g.y
    local sombra = Screen:scaleBySize(3)
    local w, h = g.w - sombra, g.h - sombra
    local r = math.floor(h / 2)
    bb:paintRoundedRect(x + sombra, y + sombra, w, h, Blitbuffer.COLOR_LIGHT_GRAY, r)
    bb:paintRoundedRect(x, y, w, h, Blitbuffer.COLOR_WHITE, r)
    bb:paintBorder(x, y, w, h, Screen:scaleBySize(1), Blitbuffer.COLOR_DARK_GRAY, r)
    local tw = TextWidget:new{ text = texto, face = fonte(TAM), fgcolor = Blitbuffer.COLOR_BLACK }
    local ts = tw:getSize()
    local d = math.max(3, Screen:scaleBySize(6))
    local passo = d + Screen:scaleBySize(5)
    local pontos_w = 3 * d + 2 * (passo - d)
    local espaco = Screen:scaleBySize(12)
    local cx = x + math.floor((w - (pontos_w + espaco + ts.w)) / 2)
    local cy = y + math.floor(h / 2)
    local cores = { Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_DARK_GRAY, Blitbuffer.COLOR_LIGHT_GRAY }
    for i = 1, 3 do
        bb:paintRoundedRect(cx + (i - 1) * passo, cy - math.floor(d / 2), d, d, cores[i], math.floor(d / 2))
    end
    tw:paintTo(bb, cx + pontos_w + espaco, y + math.floor((h - ts.h) / 2))
    tw:free()
end

-- v4: sem desfoque (o Daniel nao gostou); o modal e so a pilula no centro
local function pintarPilula(self, bb, x, y)
    self.dimen = geometria(self._lev_texto)
    desenharPilula(bb, self._lev_texto)
end

-- tamanho e posicao: sempre no centro da tela
geometria = function(texto)
    local tw = TextWidget:new{ text = texto, face = fonte(TAM) }
    local tsw, tsh = tw:getSize().w, tw:getSize().h
    tw:free()
    local pontos = Screen:scaleBySize(6) * 3 + Screen:scaleBySize(5) * 2 + Screen:scaleBySize(12)
    local sombra = Screen:scaleBySize(3)
    local pw = tsw + pontos + 2 * Screen:scaleBySize(26)
    local ph = tsh + Screen:scaleBySize(26)
    local W, H = Screen:getWidth(), Screen:getHeight()
    return Geom:new{ x = math.floor((W - pw) / 2), y = math.floor((H - ph) / 2), w = pw + sombra, h = ph + sombra }
end

-- ---------- modal generico ----------
local Modal = Widget:extend{ _lev_modal = true }
Modal.paintTo = pintarPilula
function Modal:onCloseWidget()
    if self._timeout then UIManager:unschedule(self._timeout) end
    UIManager:setDirty(nil, function() return "ui", self.dimen end)
end

local M = {}
function M.mostrar(texto)
    local dimen = geometria(texto or "Loading…")
    local m = Modal:new{ dimen = dimen, _lev_texto = texto or "Loading…" }
    UIManager:show(m, "ui", dimen, dimen.x, dimen.y)
    UIManager:forceRePaint()
    m._timeout = function() m._timeout = nil; UIManager:close(m) end
    UIManager:scheduleIn(12, m._timeout)
    return m
end
function M.fechar(m)
    if m then UIManager:close(m) end
end
-- mostra o modal, roda a acao no proximo ciclo (para o modal aparecer antes) e fecha depois
function M.durante(texto, acao)
    local m = M.mostrar(texto)
    UIManager:nextTick(function()
        local ok, err = pcall(acao)
        if not ok then logger.warn("Lev modal: erro na acao:", err) end
        UIManager:scheduleIn(0.3, function() M.fechar(m) end)
    end)
end
_G.__LEV_MODAL = M

-- ---------- aviso "Opening" do ZenOS: mesmo modal, no centro ----------
local showOriginal = UIManager.show
function UIManager:show(widget, refreshtype, refreshregion, x, y, ...)
    if type(widget) == "table" and widget._zen_opening_banner and not widget._lev_restilizado then
        widget._lev_restilizado = true
        local ok = pcall(function()
            local g = geometria("Opening…")
            widget.dimen.x, widget.dimen.y, widget.dimen.w, widget.dimen.h = g.x, g.y, g.w, g.h
            widget._lev_texto = "Opening…"
            widget.paintTo = pintarPilula
        end)
        if ok and widget.dimen then
            return showOriginal(self, widget, refreshtype, widget.dimen, widget.dimen.x, widget.dimen.y, ...)
        end
    end
    return showOriginal(self, widget, refreshtype, refreshregion, x, y, ...)
end

-- ---------- progresso do motor de EPUB: mesmo modal, no lugar da barrinha do canto ----------
local function modalNaTela()
    for _, j in ipairs(UIManager._window_stack or {}) do
        local w = j.widget
        if w and (w._lev_modal or w._lev_restilizado) then return true end
    end
    return false
end
local ok_rr, ReaderRolling = pcall(require, "apps/reader/modules/readerrolling")
if ok_rr and ReaderRolling and ReaderRolling.showEngineProgress then
    local INICIO = 2 -- segundos antes de mostrar (como o original)
    function ReaderRolling:showEngineProgress(percent)
        if percent == nil then -- terminou: a tela inteira sera redesenhada pelo leitor
            self._lev_prog_t, self._lev_prog_feito = nil, nil
            return
        end
        local agora = os.time()
        if not self._lev_prog_t then self._lev_prog_t = agora; return end
        if self._lev_prog_feito or agora - self._lev_prog_t < INICIO then return end
        self._lev_prog_feito = true
        if modalNaTela() then return end -- o "Opening…" ja esta na tela
        local texto = (self.ui and self.ui.document and self.ui.document.been_rendered) and "Loading…" or "Opening…"
        -- pinta direto na tela: o UIManager so volta a rodar quando o motor terminar
        pcall(function()
            desenharPilula(Screen.bb, texto)
            local g = geometria(texto)
            Screen:refreshUI(g.x, g.y, g.w, g.h)
        end)
    end
end

-- ---------- sair do livro (Inicio, Biblioteca, abas): "Loading…" ----------
userpatch.registerPatchPluginFunc("zenos", function()
    local ok, nav = pcall(require, "common/library_navigation")
    if not ok or not nav or not nav.showFromReader or nav._lev_modal then return end
    nav._lev_modal = true
    local original = nav.showFromReader
    nav.showFromReader = function(...)
        local m = M.mostrar("Loading…")
        local r = { pcall(original, ...) }
        UIManager:scheduleIn(0.4, function() M.fechar(m) end)
        if not r[1] then error(r[2]) end
        return unpack(r, 2)
    end
end)

-- voltar do livro pelo menu / botao Back do KOReader (sem passar pelo ZenOS)
local ReaderUI = require("apps/reader/readerui")
local voltarOriginal = ReaderUI.onHome
if voltarOriginal then
    function ReaderUI:onHome(...)
        local m = M.mostrar("Loading…")
        local r = { pcall(voltarOriginal, self, ...) }
        UIManager:scheduleIn(0.4, function() M.fechar(m) end)
        if not r[1] then error(r[2]) end
        return unpack(r, 2)
    end
end

logger.info("Lev: modal de carregamento padrao ativo")
