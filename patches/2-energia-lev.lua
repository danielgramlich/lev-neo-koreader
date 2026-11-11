-- Lev Neo (2026-11-11, v2): economia de bateria sem perder a qualidade da tela.
-- O lancador do KOReader para Bookeen (/mnt/app/boordr) trava o processador em 1 GHz o
-- tempo todo (~260 mA parado). A v1 usava o modo "interactive", que derruba para 60 MHz:
-- economizava, mas a tela de tinta (cuja atualizacao depende do processador no A13)
-- ficava pior e tudo mais lento.
-- v2: velocidade maxima sempre que ha toque, botao ou algo para desenhar (antes de
-- desenhar), e 60 MHz so depois de 8 s sem nada acontecendo.
-- O tempo para dormir sozinho fica em settings.reader.lua (auto_suspend_timeout_seconds).
-- Para desfazer: apague este arquivo (o lancador volta a usar 1 GHz fixo no proximo inicio).
local UIManager = require("ui/uimanager")
local logger = require("logger")

local CPU = "/sys/devices/system/cpu/cpu0/cpufreq/"
local RAPIDO, LENTO = "1008000", "60000"
local OCIOSO = 8 -- segundos sem atividade ate baixar a velocidade

local estado, ultimo, ativo = nil, os.time(), false

local function escrever(arquivo, valor)
    local f = io.open(CPU .. arquivo, "w")
    if not f then return false end
    f:write(valor)
    f:close()
    return true
end

local function velocidade(v)
    if estado == v then return end
    if escrever("scaling_setspeed", v) then estado = v end
end

local function atividade()
    ultimo = os.time()
    if ativo and estado ~= RAPIDO then velocidade(RAPIDO) end
end

local function vigiar()
    if ativo and estado == RAPIDO and os.time() - ultimo >= OCIOSO then velocidade(LENTO) end
    UIManager:scheduleIn(3, vigiar)
end

-- liga o modo manual ("userspace") e comeca rapido
UIManager:scheduleIn(2, function()
    if escrever("scaling_governor", "userspace") then
        ativo = true
        estado = nil
        velocidade(RAPIDO)
        ultimo = os.time()
        vigiar()
        logger.info("Lev energia: rapido ao usar, 60 MHz apos", OCIOSO, "s parado")
    else
        logger.warn("Lev energia: nao consegui ajustar o processador")
    end
end)

-- toque, botoes e qualquer pedido de desenho: acelera antes de desenhar
local entradaOriginal = UIManager.handleInputEvent
function UIManager:handleInputEvent(...)
    atividade()
    return entradaOriginal(self, ...)
end
local sujarOriginal = UIManager.setDirty
function UIManager:setDirty(...)
    atividade()
    return sujarOriginal(self, ...)
end
local forcarOriginal = UIManager.forceRePaint
function UIManager:forceRePaint(...)
    atividade()
    return forcarOriginal(self, ...)
end

-- ao acordar: o modo manual pode ter sido trocado; reaplica e fica rapido
local Device = require("device")
if Device.resume then
    local acordarOriginal = Device.resume
    Device.resume = function(...)
        if ativo then escrever("scaling_governor", "userspace"); estado = nil; atividade() end
        return acordarOriginal(...)
    end
end
