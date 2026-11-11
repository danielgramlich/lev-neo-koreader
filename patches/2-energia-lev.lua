-- Lev Neo (2026-11-11): economia de bateria.
-- O lancador do KOReader para Bookeen (/mnt/app/boordr) trava o processador em
-- "performance" (1 GHz o tempo todo): ~260 mA parado no Inicio. No modo "interactive"
-- ele so acelera quando ha toque ou virada de pagina: ~163 mA medidos (-37%).
-- Aplica ao abrir o KOReader e de novo ao acordar.
-- O tempo para dormir sozinho fica em settings.reader.lua (auto_suspend_timeout_seconds,
-- 300 s = 5 min). Para desfazer: apague este arquivo (o lancador volta a usar performance
-- no proximo inicio).
local UIManager = require("ui/uimanager")
local logger = require("logger")

local GOVERNADOR = "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
local MODO = "interactive"

local function aplicar()
    local f = io.open(GOVERNADOR, "w")
    if not f then return false end
    f:write(MODO)
    f:close()
    local r = io.open(GOVERNADOR)
    local atual = r and r:read("*l")
    if r then r:close() end
    return atual == MODO
end

UIManager:scheduleIn(2, function()
    logger.info("Lev energia: processador em", MODO, aplicar() and "(ok)" or "(falhou)")
end)

-- ao acordar, garante o modo de novo
local Device = require("device")
if Device.resume then
    local acordarOriginal = Device.resume
    Device.resume = function(...)
        local r = { acordarOriginal(...) }
        UIManager:scheduleIn(1, function() pcall(aplicar) end)
        return unpack(r)
    end
end
