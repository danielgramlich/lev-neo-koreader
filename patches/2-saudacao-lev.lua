-- Lev Neo (2026-11-06): saudacao no topo do Inicio do ZenOS.
-- "Boa noite, Daniel" (Literata, como na leitura) a esquerda e a data por extenso
-- ("sexta, 6 de novembro") a direita, numa faixa fina no topo do Inicio.
-- Usa o registro oficial de faixas do Inicio do ZenOS; a faixa "lev_saudacao" e
-- ligada e posicionada em settings/ZenOS/home.lua (rows).
-- Nome: defina ["lev_nome"] em settings.reader.lua (ver README).
-- Para desfazer: apague este arquivo e a linha "lev_saudacao" de rows em home.lua.
local userpatch = require("userpatch")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local logger = require("logger")
local Screen = Device.screen

-- nome da saudacao: settings.reader.lua -> ["lev_nome"] = "Seu nome" (padrao "reader")
local function nome()
    local n = G_reader_settings and G_reader_settings:readSetting("lev_nome")
    return (type(n) == "string" and n ~= "") and n or "reader"
end
local DIAS = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" }
local MESES = { "January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December" }

local function faceUI(tamanho)
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, face = pcall(lf.getFace, tamanho)
        if ok2 and face then return face end
    end
    return Font:getFace("cfont", tamanho)
end

local function faceTitulo(tamanho)
    local ok, face = pcall(Font.getFace, Font, "literata/Literata-Bold.ttf", tamanho)
    if ok and face then return face end
    return faceUI(tamanho)
end

local function saudacao()
    local h = tonumber(os.date("%H")) or 12
    local s = (h >= 5 and h < 12) and "Good morning" or (h >= 12 and h < 18) and "Good afternoon" or "Good evening"
    return s .. ", " .. nome()
end

local function dataExtenso()
    local t = os.date("*t")
    return string.format("%s, %s %d", DIAS[t.wday], MESES[t.month], t.day)
end

local function construir(ctx)
    local W, H = ctx.width, ctx.height
    local titulo = TextWidget:new{ text = saudacao(), face = faceTitulo(24), fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = math.floor(W * 0.62) }
    local data = TextWidget:new{ text = dataExtenso(), face = faceUI(15), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        max_width = math.floor(W * 0.36) }
    -- mesmas margens laterais das outras faixas; texto assentado embaixo, perto do conteudo
    local pad_esq, pad_dir = Screen:scaleBySize(8), Screen:scaleBySize(4)
    local th = math.max(titulo:getSize().h, data:getSize().h)
    local pad_topo = math.max(0, H - th - Screen:scaleBySize(10))
    local dimen = Geom:new{ w = W - pad_esq - pad_dir, h = th }
    return FrameContainer:new{
        width = W, height = H, padding = 0, bordersize = 0, background = Blitbuffer.COLOR_WHITE,
        padding_left = pad_esq, padding_right = pad_dir, padding_top = pad_topo,
        OverlapGroup:new{ dimen = dimen,
            LeftContainer:new{ dimen = dimen, titulo },
            RightContainer:new{ dimen = dimen, data },
        },
    }
end

userpatch.registerPatchPluginFunc("zenos", function()
    local ok, Registry = pcall(require, "modules/filebrowser/patches/home/components/registry")
    if not ok or not Registry or not Registry.register then
        logger.warn("Lev saudacao: registro do Inicio do ZenOS nao encontrado")
        return
    end
    Registry.register("lev_saudacao", function(ctx)
        local ok_b, w = pcall(construir, ctx)
        if ok_b then return w end
        logger.warn("Lev saudacao: erro ao montar:", w)
    end, { label = "Greeting", size = "xs" })
    logger.info("Lev: saudacao no topo do Inicio ativa")
end)
