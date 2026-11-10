-- Lev Neo (2026-11-09): tela de descanso com a capa inteira (redimensionada, sem cortar,
-- sem esticar, sem zoom) e as sobras da tela preenchidas com a cor da borda da propria
-- capa. A tela do Lev (3:4) e mais larga que uma capa de livro (2:3); com fundo da mesma
-- cor da borda, a capa parece ocupar a tela toda (capa preta -> laterais pretas, etc.).
-- Para desfazer: apague este arquivo (koreader/patches/2-descanso-lev.lua).
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")

-- sempre a capa inteira: sem cortar e sem esticar
G_reader_settings:makeFalse("screensaver_images_crop_to_fit")
G_reader_settings:makeFalse("screensaver_stretch_images")

local Screensaver = require("ui/screensaver")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")

local function cinza(bb, x, y)
    local ok, c = pcall(bb.getPixel, bb, x, y)
    if not ok or not c then return nil end
    local ok8, c8 = pcall(function() return c:getColor8() end)
    return ok8 and c8 and tonumber(c8.a) or nil
end

-- mediana dos tons das bordas por onde vai sobrar espaco (laterais ou topo/base)
local function corDaBorda(bb, tela_w, tela_h)
    local w, h = bb:getWidth(), bb:getHeight()
    if w < 4 or h < 4 then return nil end
    local valores = {}
    local laterais = (w / h) < (tela_w / tela_h)
    if laterais then
        for y = 0, h - 1, math.max(1, math.floor(h / 120)) do
            for _, x in ipairs({ 0, 1, 2, w - 3, w - 2, w - 1 }) do
                local v = cinza(bb, x, y); if v then valores[#valores + 1] = v end
            end
        end
    else
        for x = 0, w - 1, math.max(1, math.floor(w / 120)) do
            for _, y in ipairs({ 0, 1, 2, h - 3, h - 2, h - 1 }) do
                local v = cinza(bb, x, y); if v then valores[#valores + 1] = v end
            end
        end
    end
    if #valores == 0 then return nil end
    table.sort(valores)
    return valores[math.floor(#valores / 2) + 1]
end

local cor_atual -- cor calculada para a tela de descanso que esta sendo montada

local showOriginal = Screensaver.show
function Screensaver:show(...)
    cor_atual = nil
    if self.screensaver_type == "cover" and self.image then
        local Screen = require("device").screen
        local ok, v = pcall(corDaBorda, self.image, Screen:getWidth(), Screen:getHeight())
        if ok and v then cor_atual = Blitbuffer.Color8(v) end
    end
    local r = showOriginal(self, ...)
    cor_atual = nil
    return r
end

local newOriginal = ScreenSaverWidget.new
function ScreenSaverWidget:new(o, ...)
    if cor_atual and type(o) == "table" and o.widget then
        o.background = cor_atual
    end
    return newOriginal(self, o, ...)
end

logger.info("Lev: tela de descanso com capa inteira e borda da cor da capa")
