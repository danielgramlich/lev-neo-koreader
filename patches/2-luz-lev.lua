-- Lev Neo (2026-11-06): luz frontal.
-- 1) Curva de brilho percebida: o KOReader varia o PWM de forma linear, mas o olho
--    percebe brilho de forma logaritmica; acima de ~20% de duty tudo parece "aceso".
--    Aplica gama 2.2: metade da barra = ~19% de duty, e a barra inteira fica uniforme.
-- 2) Descanso: com o cabo USB ligado o kernel recusa a suspensao
--    (sw_usb_udc failed to suspend: -16). Mesmo assim a luz fica apagada
--    enquanto a tela de descanso estiver visivel.
-- Para desfazer: apague este arquivo (koreader/patches/2-luz-lev.lua).

local Device = require("device")
local logger = require("logger")

local GAMA = 2.2
local MAX = 255

local powerd = Device:getPowerDevice()

local function paraHW(i)
    if not i or i <= 0 then return 0 end
    local hw = math.floor(MAX * (i / MAX) ^ GAMA + 0.5)
    if hw < 1 then hw = 1 end
    if hw > MAX then hw = MAX end
    return hw
end

local function deHW(hw)
    if not hw or hw <= 0 then return 0 end
    local i = math.floor(MAX * (hw / MAX) ^ (1 / GAMA) + 0.5)
    if i < 1 then i = 1 end
    if i > MAX then i = MAX end
    return i
end

local setOriginal = powerd.setIntensityHW
local getOriginal = powerd.frontlightIntensityHW

-- 4) Luz travada: no Lev Neo, depois que a luz e APAGADA (frontlight 255: tela de descanso,
--    botao de luz) ou o aparelho suspende, o PWM continua aceitando valores mas a luz para
--    de mudar. Passar pelo brilho maximo (frontlight 0) reinicia o circuito. Toda apagada
--    ou suspensao marca a luz como travada; o proximo acendimento passa um instante pelo
--    maximo e ja aplica o nivel pedido.
local travada = true -- ao iniciar nao sabemos o estado: o primeiro ajuste destrava

function powerd:setIntensityHW(intensity)
    if not intensity or intensity <= 0 then
        travada = true -- apagar trava o circuito ate passar pelo maximo
    elseif travada then
        os.execute("/bin/frontlight 0") -- destrava (instante no maximo)
        travada = false
        logger.info("Lev: luz destravada")
    end
    return setOriginal(self, paraHW(intensity))
end

function powerd:frontlightIntensityHW()
    return deHW(getOriginal(self))
end

-- Reler a intensidade atual na nova escala (foi lida na escala antiga ao iniciar)
powerd.fl_intensity = powerd:frontlightIntensityHW()

-- 3) Suspensao: o lancador (/mnt/app/boordr) bloqueia /sys/power/state no boot para
--    impedir a suspensao rapida do ebrmain (que congela o PWM e trava o brilho) e
--    deixa o arquivo real acessivel em /tmp/power_state, so para o KOReader.
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local ESTADO_REAL = "/tmp/power_state"
local writeOriginal = ffiUtil.writeToSysfs
ffiUtil.writeToSysfs = function(val, file, ...)
    if file == "/sys/power/state" and lfs.attributes(ESTADO_REAL, "mode") == "file" then
        file = ESTADO_REAL
    end
    if file == ESTADO_REAL or file == "/sys/power/state" then
        travada = true -- suspensao ou standby: a luz vai precisar ser destravada
    end
    return writeOriginal(val, file, ...)
end

local suspendOriginal = Device.suspend
function Device:suspend(...)
    local r = suspendOriginal(self, ...)
    if self.screen_saver_mode then
        -- suspensao recusada (ou acordou com a tela de descanso ainda ativa): luz apagada
        -- direto no driver (255 = apagada), sem mudar o estado "luz acesa" do
        -- KOReader, para que ao acordar ele reacenda no nivel escolhido
        os.execute("/bin/frontlight 255")
        travada = true
        logger.info("Lev: luz apagada no descanso")
    elseif powerd:isFrontlightOn() then
        -- acordou direto para o uso: reacende no nivel escolhido (e destrava)
        powerd:setIntensityHW(powerd.fl_intensity)
    end
    return r
end

logger.info("Lev: patch de luz ativo (gama", GAMA, ")")
