-- Lev Neo (2026-11-06): navegacao pelos 3 botoes fisicos (v2, esquema do Daniel).
-- O touch do Lev nao e confiavel, entao tudo pode ser feito pelos botoes.
-- O touch continua ativo para virar pagina e para os botoes de dialogos.
--
-- Botoes: lateral direita = codigo 407, lateral esquerda = 158, inicio = 139.
--
-- EM QUALQUER TELA
--   inicio (1 toque)    = abre / fecha o menu superior (do livro ou da biblioteca)
--   inicio (segurado ~0,8 s)  = vai para a tela Inicio do ZenOS (fecha o livro, se houver)
-- BIBLIOTECA E LISTAS COM PAGINAS
--   esquerda / direita            = pagina anterior / seguinte
-- MENUS E DIALOGOS
--   esquerda / direita            = seleciona o item anterior / seguinte
--   esquerda segurado             = volta (fecha o menu / pasta de cima)
--   direita segurado              = confirma / abre o item selecionado
-- LENDO (livro aberto, sem menu por cima)
--   esquerda / direita            = pagina anterior / seguinte
--   esquerda / direita segurado   = capitulo anterior / seguinte
-- MENU ABERTO EM AJUSTES RAPIDOS (painel com o brilho)
--   direita / esquerda            = clarear / escurecer um nivel
-- TELA DO SPOTIFY
--   esquerda / direita            = musica anterior / seguinte
--   direita segurado              = tocar / pausar
--   esquerda segurado             = sair da tela
--
-- Para desfazer: apague este arquivo (koreader/patches/2-botoes-lev.lua).

local Device = require("device")
local Event = require("ui/event")
local Key = require("device/key")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local function yes() return true end
Device.hasDPad = yes
Device.hasFewKeys = yes

local input = Device.input
local PRESS, RELEASE = 1, 0

local function tecla(nome)
    return Event:new("KeyPress", Key:new(nome, input.modifiers))
end

local function enviar(ev)
    if ev then UIManager:sendEvent(ev) end
end

-- painel de Ajustes rapidos (com o controle de brilho) aberto no menu?
local function painelBrilhoAberto(top)
    local b = rawget(_G, "__LEV_BRILHO")
    local tm = b and b.tm
    if not tm or not tm.item_table or not tm.item_table.panel then return false end
    return top == tm or top == tm.show_parent or (type(top[1]) == "table" and top[1] == tm)
end

-- "spotify", "brilho", "ler", "biblioteca" ou "menu"
local function contexto()
    local top = UIManager:getTopmostVisibleWidget()
    if not top then return "menu" end
    if top._lev_spotify then return "spotify" end -- painel do plugin Spotify
    if painelBrilhoAberto(top) then return "brilho" end -- menu aberto em Ajustes rapidos
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_r and ReaderUI.instance and top == ReaderUI.instance then
        return "ler"
    end
    local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok_f and FileManager.instance and top == FileManager.instance then
        return "biblioteca"
    end
    -- outras listas paginadas (telas do ZenOS: Inicio, colecoes, historico...)
    if top.page_num and top.item_table and not top.item_table.panel and not top.bar then
        return "lista"
    end
    return "menu"
end

-- ---------- botoes laterais: toque curto ao soltar, longo ao repetir ----------
local function lateral(acao_curta, acao_longa)
    local s = {}
    return function(ev)
        if ev.value == PRESS then
            s.ctx = contexto()
            s.feito = false
            return
        elseif ev.value == RELEASE then
            if s.feito then return end
            s.feito = true
            return acao_curta(s.ctx or contexto())
        else -- repeticao: botao segurado
            if s.feito then return end
            s.feito = true
            return acao_longa(s.ctx or contexto())
        end
    end
end

input.event_map_adapter = input.event_map_adapter or {}

-- Painel do Spotify aberto: laterais = proxima / anterior musica
local function lateralSpotify(lado)
    local top = UIManager:getTopmostVisibleWidget()
    if top and top.levLateral then top:levLateral(lado) end
end

input.event_map_adapter.LPgFwd = lateral(
    function(ctx) -- curto
        if ctx == "ler" then return tecla("LPgFwd") end
        if ctx == "spotify" then return lateralSpotify("direita") end
        if ctx == "brilho" then return _G.__LEV_BRILHO.clarear() end
        if ctx == "biblioteca" or ctx == "lista" then return tecla("LPgFwd") end -- proxima pagina
        return tecla("Down")
    end,
    function(ctx) -- segurado: avancar (lendo) / confirmar (menus e biblioteca)
        if ctx == "ler" then return Event:new("GotoNextChapter") end
        if ctx == "spotify" then return lateralSpotify("direita_longo") end
        return tecla("Press") -- abre / confirma o item selecionado
    end
)

input.event_map_adapter.LPgBack = lateral(
    function(ctx) -- curto
        if ctx == "ler" then return tecla("LPgBack") end
        if ctx == "spotify" then return lateralSpotify("esquerda") end
        if ctx == "brilho" then return _G.__LEV_BRILHO.escurecer() end
        if ctx == "biblioteca" or ctx == "lista" then return tecla("LPgBack") end -- pagina anterior
        return tecla("Up")
    end,
    function(ctx) -- segurado: voltar
        if ctx == "ler" then return Event:new("GotoPrevChapter") end
        if ctx == "spotify" then return lateralSpotify("esquerda_longo") end
        if ctx == "biblioteca" then return Event:new("FolderUp") end
        return tecla("Left") -- fecha o menu / dialogo (modo poucas teclas)
    end
)

-- ---------- botao inicio: 1 toque = abre/fecha o menu superior; segurado = Home ----------
local h = { segurou = false }

-- Menu superior do livro (se houver livro aberto) ou da biblioteca
local function menuAtual()
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_r and ReaderUI.instance and ReaderUI.instance.menu then
        return ReaderUI.instance.menu, "reader"
    end
    local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok_f and FileManager.instance and FileManager.instance.menu then
        return FileManager.instance.menu, "fm"
    end
end

local function alternarMenu()
    local menu, tipo = menuAtual()
    if not menu then return enviar(tecla("Menu")) end
    if menu.menu_container then
        if tipo == "reader" and menu.onCloseReaderMenu then menu:onCloseReaderMenu()
        elseif menu.onCloseFileManagerMenu then menu:onCloseFileManagerMenu()
        else UIManager:close(menu.menu_container); menu.menu_container = nil end
    else
        menu:onShowMenu()
    end
end

-- Vai para a tela Inicio do ZenOS: fecha menus/dialogos por cima, fecha o livro
-- (se houver) do mesmo jeito que o ZenOS faz no fim de um livro, e abre a aba Inicio.
local function irParaInicio()
    local ok_r, ReaderUI = pcall(require, "apps/reader/readerui")
    local ok_f, FileManager = pcall(require, "apps/filemanager/filemanager")
    local base = {}
    if ok_r and ReaderUI.instance then base[ReaderUI.instance] = true end
    if ok_f and FileManager.instance then base[FileManager.instance] = true end
    local pilha = UIManager._window_stack or {}
    for i = #pilha, 1, -1 do
        local w = pilha[i].widget
        if base[w] then break end
        if not w.invisible then UIManager:close(w) end
    end
    UIManager:nextTick(function()
        local zen = rawget(_G, "__ZEN_UI_PLUGIN")
        if ok_r and ReaderUI.instance then
            local ok_nav, nav = pcall(require, "common/library_navigation")
            if ok_nav and nav and nav.showFromReader and zen then
                nav.showFromReader(ReaderUI.instance, zen, { open_home = true })
            else
                enviar(tecla("Home"))
            end
            return
        end
        local abrir_aba = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
        if type(abrir_aba) == "function" then
            abrir_aba("home")
        else
            enviar(tecla("Home"))
        end
    end)
end

-- Inicio: solto antes de SEGURAR_S = abre/fecha o menu; segurado = tela Inicio.
-- v7: o tempo e medido pelo relogio do proprio evento do teclado (ev.time, do kernel),
-- e nao pela hora em que o KOReader processa o evento. Antes, se a tela estava ocupada
-- atualizando, o aperto e a soltura chegavam juntos e um toque longo virava curto (e
-- vice-versa). Ao atingir o tempo, ja vai para o Inicio sem esperar soltar.
local SEGURAR_S = 0.8
local tempo = require("ui/time")

local function instante(ev)
    if ev and ev.time then
        local ok, t = pcall(tempo.timeval, ev.time)
        if ok and t then return t end
    end
    return tempo.now()
end

local function duracao(ev)
    if not h.t0 then return 0 end
    return tempo.to_s(instante(ev) - h.t0)
end

input.event_map_adapter.Home = function(ev)
    if ev.value == PRESS then
        h.segurou = false
        h.t0 = instante(ev)
        return
    elseif ev.value == RELEASE then
        local d = duracao(ev)
        local ja_foi = h.segurou
        h.t0, h.segurou = nil, false
        if ja_foi then return end
        if d >= SEGURAR_S then
            logger.info("Lev botoes: inicio segurado", string.format("%.2f s", d), "-> tela Inicio")
            irParaInicio()
        else
            logger.info("Lev botoes: inicio tocado", string.format("%.2f s", d), "-> menu")
            alternarMenu()
        end
        return
    else -- repeticao do kernel enquanto o botao esta apertado
        if h.segurou or not h.t0 then return end
        local d = duracao(ev)
        if d < SEGURAR_S then return end
        h.segurou = true
        logger.info("Lev botoes: inicio segurado", string.format("%.2f s", d), "-> tela Inicio")
        irParaInicio()
        return
    end
end

logger.info("Lev: patch de botoes v9 ativo (hasDPad + hasFewKeys)")
