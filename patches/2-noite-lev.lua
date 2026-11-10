-- Lev Neo (2026-11-10): modo noturno automatico.
-- * Das 21h as 6h o Lev entra sozinho no modo noturno; as 6h volta ao modo claro.
--   So age na virada do horario: se voce mudar na mao no meio da noite, ele respeita
--   ate a proxima virada.
-- * Botao "Auto night" nos Ajustes rapidos do ZenOS (ao lado de "Night") liga e desliga
--   a automacao: preenchido = ligada. Tambem aparece nas acoes do KOReader
--   (Dispatcher "Auto night mode").
-- * Preferencias em settings.reader.lua: lev_noite_auto (true/false),
--   lev_noite_inicio (21) e lev_noite_fim (6).
-- Para desfazer: apague este arquivo e o botao "lev_noite_auto" em settings/ZenOS/config.lua.
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local userpatch = require("userpatch")
local logger = require("logger")

local ACAO = "lev_noite_auto"

local function ligada() return G_reader_settings:nilOrTrue("lev_noite_auto") end
local function inicio() return tonumber(G_reader_settings:readSetting("lev_noite_inicio")) or 21 end
local function fim() return tonumber(G_reader_settings:readSetting("lev_noite_fim")) or 6 end

local function periodoAtual()
    local h = tonumber(os.date("%H"))
    local i, f = inicio(), fim()
    local noite
    if i > f then noite = h >= i or h < f else noite = h >= i and h < f end
    return noite and "noite" or "dia"
end

local function aplicarNoite(ligar)
    local atual = G_reader_settings:isTrue("night_mode")
    if atual ~= ligar then
        UIManager:broadcastEvent(Event:new("SetNightMode", ligar))
        logger.info("Lev noite: modo noturno", ligar and "ligado" or "desligado", "pela automacao")
    end
end

-- age so quando o periodo muda (ou na primeira vez, se ja for noite)
local function verificar()
    if not ligada() then return end
    local p = periodoAtual()
    local anterior = G_reader_settings:readSetting("lev_noite_periodo")
    if p ~= anterior then
        if p == "noite" then aplicarNoite(true)
        elseif anterior ~= nil then aplicarNoite(false) end
        G_reader_settings:saveSetting("lev_noite_periodo", p)
        -- grava na hora (o modo noturno e a virada), sem esperar o KOReader suspender
        UIManager:scheduleIn(1, function() G_reader_settings:flush() end)
    end
end

local function ciclo()
    pcall(verificar)
    UIManager:scheduleIn(60, ciclo)
end
UIManager:scheduleIn(5, ciclo)

local function avisar(texto)
    local ok, Notification = pcall(require, "ui/widget/notification")
    if ok and Notification then Notification:notify(texto, Notification.SOURCE_ALWAYS_SHOW) end
end

local function alternar()
    local nova = not ligada()
    G_reader_settings:saveSetting("lev_noite_auto", nova)
    if nova then
        G_reader_settings:delSetting("lev_noite_periodo") -- reavalia ja
        pcall(verificar)
        avisar(string.format("Auto night mode on (%d:00 – %d:00)", inicio(), fim()))
    else
        avisar("Auto night mode off")
    end
    G_reader_settings:flush()
end
_G.__LEV_NOITE = { alternar = alternar, ligada = ligada }

-- acao do KOReader (usada pelo botao dos Ajustes rapidos e por gestos, se quiser)
local Dispatcher = require("dispatcher")
pcall(Dispatcher.registerAction, Dispatcher, ACAO, {
    category = "none", event = "LevNoiteAuto", title = "Auto night mode", general = true,
})
local executarOriginal = Dispatcher.execute
function Dispatcher:execute(acoes, ...)
    if type(acoes) == "table" and acoes[ACAO] then
        UIManager:nextTick(alternar)
        return
    end
    return executarOriginal(self, acoes, ...)
end

-- estado do botao (preenchido = automacao ligada) no ZenOS
userpatch.registerPatchPluginFunc("zenos", function()
    local ok, DA = pcall(require, "common/dispatch_action")
    if not ok or not DA or not DA.isActionActive then return end
    local ativos = userpatch.getUpValue(DA.isActionActive, "zen_action_active")
    if type(ativos) == "table" then
        ativos[ACAO] = function() return ligada() end
    end
end)

-- ao acordar, confere o horario na hora
local Device = require("device")
if Device.resume then
    local acordarOriginal = Device.resume
    Device.resume = function(...)
        local r = { acordarOriginal(...) }
        UIManager:scheduleIn(2, function() pcall(verificar) end)
        return unpack(r)
    end
end

logger.info("Lev: modo noturno automatico", ligada() and "ligado" or "desligado")
