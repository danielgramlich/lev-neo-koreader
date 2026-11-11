-- Lev Neo (2026-11-11): conexao Wi-Fi com um modal so.
-- Antes, ao ligar o Wi-Fi o KOReader mostrava varias caixas seguidas ("Turning on Wi-Fi…",
-- "Connecting…", "Scanning for networks…", "Connected to network <nome>", "You can now
-- retry…"). Agora aparece so o modal padrao do Lev ("Connecting to Wi-Fi…") do inicio ao
-- fim da conexao. Se falhar, uma mensagem curta: "Couldn't connect to Wi-Fi".
-- Perguntas (ex.: "ligar o Wi-Fi?") e a lista de redes continuam aparecendo normalmente.
-- Para desfazer: apague este arquivo (koreader/patches/2-wifi-lev.lua).
local UIManager = require("ui/uimanager")
local logger = require("logger")

local LIMITE = 60   -- segundos maximos com o modal na tela
local SOBRA = 6     -- segundos depois do fim em que avisos atrasados ainda sao escondidos

local sessao = { ativa = false, fim = 0 }

-- avisos tecnicos de rede que somem durante a conexao
local PADROES = {
    "turning on wi%-fi", "turning off wi%-fi", "connecting to", "connected to network",
    "waiting for network", "scanning", "you can now retry",
    "previous connection attempt", "obtaining", "wi%-fi", "network",
}
local FALHAS = { "error connecting to the network", "connection failed" }

local function textoDe(w)
    local t = type(w) == "table" and rawget(w, "text")
    return type(t) == "string" and t:lower() or nil
end

local function bate(texto, lista)
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

-- esconde os avisos tecnicos enquanto conecta (e logo depois)
local mostrarOriginal = UIManager.show
function UIManager:show(widget, ...)
    local texto = textoDe(widget)
    local eh_aviso = texto and not (type(widget) == "table" and rawget(widget, "_lev_wifi"))
        and (widget.ok_callback == nil and widget.buttons == nil) -- nunca esconde perguntas
    if eh_aviso then
        if texto:find("turning on wi%-fi") or texto:find("connecting to wi%-fi")
                or texto:find("^scanning") or texto:find("waiting for network") then
            abrir()
        end
        local na_janela = sessao.ativa or (os.time() - sessao.fim) <= SOBRA
        if na_janela and bate(texto, FALHAS) then
            fechar("falha")
            avisoFalha()
            return
        end
        if na_janela and bate(texto, PADROES) then
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
