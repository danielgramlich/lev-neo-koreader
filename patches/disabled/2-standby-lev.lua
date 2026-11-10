-- Lev Neo (2026-11-06): suspensao rapida (standby) so com a luz APAGADA.
-- A suspensao congela o PWM da luz frontal, por isso a suspensao rapida do
-- ebrmain fica bloqueada (ver 2-luz-lev.lua). Este patch devolve a economia de
-- bateria pelo mecanismo do proprio KOReader (AutoSuspend > standby): alguns
-- segundos depois da ultima interacao o Lev dorme, e acorda ao tocar ou apertar
-- um botao. Regras: so dorme com a luz apagada (e o KOReader ja nao faz standby
-- com o Wi-Fi ligado).
-- Para desfazer: apague este arquivo (koreader/patches/2-standby-lev.lua).
local Device = require("device")
local ffiUtil = require("ffi/util")
local logger = require("logger")

Device.canStandby = function() return true end

function Device:standby(max_duration)
    local powerd = self:getPowerDevice()
    if powerd and powerd:isFrontlightOn() then
        return -- luz acesa: dormir congelaria o brilho
    end
    ffiUtil.usleep(90000) -- deixa a tela terminar a atualizacao
    -- /sys/power/state e redirecionado para /tmp/power_state pelo 2-luz-lev.lua
    local ret = ffiUtil.writeToSysfs("mem", "/sys/power/state")
    if not ret then
        logger.dbg("Lev standby: recusado pelo kernel (cabo USB ligado?)")
    end
end

logger.info("Lev: standby ativo (so com a luz apagada)")
