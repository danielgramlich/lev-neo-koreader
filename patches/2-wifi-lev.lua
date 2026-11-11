-- Lev Neo (2026-11-11): conexao Wi-Fi com um modal so.
-- Antes, ao ligar o Wi-Fi o KOReader mostrava varias caixas seguidas ("Turning on Wi-Fi…",
-- "Connecting…", "Scanning for networks…", "Connected to network <nome>", "You can now
-- retry…"). Agora aparece so o modal padrao do Lev ("Connecting to Wi-Fi…") do inicio ao
-- fim da conexao. Se falhar, uma mensagem curta: "Couldn't connect to Wi-Fi".
-- v2: durante a conexao nenhum aviso do sistema aparece (antes so os que citavam Wi-Fi/rede;
-- faltavam "Authenticating…", os passos do driver e os codigos CTRL-EVENT).
-- Perguntas (ex.: "ligar o Wi-Fi?") e a lista de redes continuam aparecendo normalmente.
-- Para desfazer: apague este arquivo (koreader/patches/2-wifi-lev.lua).
local UIManager = require("ui/uimanager")
local logger = require("logger")

local LIMITE = 60   -- segundos maximos com o modal na tela
local SOBRA = 6     -- segundos depois do fim em que avisos atrasados ainda sao escondidos

local sessao = { ativa = false, fim = 0 }

-- textos que indicam que uma conexao comecou (abrem o modal)
local INICIO = {
    "turning on wi%-fi", "connecting", "scanning", "waiting for network", "authenticat",
    "trying", "associat", "handshake", "obtaining",
}
-- textos de falha (trocados por uma mensagem curta)
local FALHAS = {
    "error connecting", "connection failed", "failed to authenticate", "timed out", "couldn't connect",
}

local InfoMessage = require("ui/widget/infomessage")
local okN, Notification = pcall(require, "ui/widget/notification")

-- e um aviso simples (InfoMessage / Notification)? Perguntas e listas nunca entram aqui.
local function ehAviso(w)
    if type(w) ~= "table" or rawget(w, "_lev_wifi") then return false end
    local mt, n = getmetatable(w), 0
    while mt and n < 20 do
        if mt == InfoMessage or (okN and mt == Notification) then return true end
        mt, n = getmetatable(mt), n + 1
    end
    return false
end

local function textoDe(w)
    local t = type(w) == "table" and rawget(w, "text")
    return type(t) == "string" and t:lower() or nil
end

local function bate(texto, lista)
    if not texto then return false end
    for _, p in ipairs(lista) do
        if texto:find(p) then return true end
    end
    return false
end

local function fechar(motivo)
    if not sessao.ativa then return end
    sessao.ativa = false
    sessao.fim = os.time()
    if sessao.timeout then UIManager:unschedule(sessao.timeout); sessao.timeout = nil end
    local M = rawget(_G, "__LEV_MODAL")
    if M and sessao.modal then M.fechar(sessao.modal) end
    sessao.modal = nil
    logger.info("Lev wifi: modal fechado (" .. tostring(motivo) .. ")")
end

local function abrir()
    if sessao.ativa then return end
    sessao.ativa = true
    local M = rawget(_G, "__LEV_MODAL")
    if M then sessao.modal = M.mostrar("Connecting to Wi-Fi…", LIMITE + 5) end
    sessao.timeout = function() sessao.timeout = nil; fechar("tempo esgotado") end
    UIManager:scheduleIn(LIMITE, sessao.timeout)
    logger.info("Lev wifi: conectando (um modal so)")
end

local function avisoFalha()
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = "Couldn't connect to Wi-Fi", timeout = 3, _lev_wifi = true })
end

-- enquanto conecta (e logo depois), nenhum aviso do sistema aparece: so o modal do Lev.
-- Isso inclui "Authenticating…", os passos do driver ("Trying to associate…", codigos
-- CTRL-EVENT…), "Authenticated", "Connected to network…" e os avisos do ZenOS.
local mostrarOriginal = UIManager.show
function UIManager:show(widget, ...)
    if ehAviso(widget) then
        local texto = textoDe(widget) or ""
        if not sessao.ativa and bate(texto, INICIO) then abrir() end
        local na_janela = sessao.ativa or (os.time() - sessao.fim) <= SOBRA
        if na_janela then
            if bate(texto, FALHAS) then
                fechar("falha")
                avisoFalha()
            end
            return -- some: o modal do Lev ja mostra que esta conectando
        end
        if texto:find("turning off wi%-fi") then return end
    end
    return mostrarOriginal(self, widget, ...)
end

-- inicio e fim pelos eventos de rede do KOReader
local broadcastOriginal = UIManager.broadcastEvent
function UIManager:broadcastEvent(evento, ...)
    local nome = type(evento) == "table" and evento.handler
    if nome == "onNetworkConnecting" then
        abrir()
    elseif nome == "onNetworkConnected" then
        fechar("conectado")
    elseif nome == "onNetworkDisconnected" or nome == "onNetworkDisconnecting" then
        fechar("desligado")
    end
    return broadcastOriginal(self, evento, ...)
end

logger.info("Lev: Wi-Fi com um modal so ativo")
