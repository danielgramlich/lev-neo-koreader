-- Lev Neo (2026-11-09): controle de brilho do menu (Ajustes rapidos do ZenOS) facil de
-- acertar com o touch impreciso do Lev.
-- Antes: barra fina de 0 a 255 e botoes - / + que andavam de 1 em 1.
-- Agora: trilha de 8 segmentos (indicador) e botoes redondos - / +; metade esquerda da fileira
-- escurece e metade direita clareia; com o painel aberto, as laterais tambem ajustam. Os - / +
-- andam um bloco por vez; - no primeiro nivel apaga a luz, + com a luz apagada reacende.
-- Os niveis ja passam pela curva de brilho do patch 2-luz-lev.lua (gama 2.2).
-- Substitui o construtor "modules/menu/patches/brightness_slider" do ZenOS antes de o
-- ZenOS carregar (patches "2-" rodam antes dos plugins).
-- Para desfazer: apague este arquivo (koreader/patches/2-brilho-ui-lev.lua).
local logger = require("logger")

local NIVEIS = 8

local function construir(touch_menu, opts)
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Font = require("ui/font")
    local Screen = Device.screen

    local powerd = opts.powerd
    local refs = opts.refs
    local show_parent = touch_menu.show_parent
    local fl_max = powerd.fl_max or 255
    local inner = opts.inner_width

    local function face(tam)
        local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
        if ok and lf and lf.getFace then
            local ok2, f = pcall(lf.getFace, tam)
            if ok2 and f then return f end
        end
        return Font:getFace("cfont", tam)
    end

    local function valorDoNivel(n) return math.floor(fl_max * n / NIVEIS + 0.5) end
    local function nivelAtual()
        if powerd.isFrontlightOff and powerd:isFrontlightOff() then return 0 end
        local v = powerd:frontlightIntensity() or 0
        if v <= 0 then return 0 end
        return math.max(1, math.min(NIVEIS, math.floor(v * NIVEIS / fl_max + 0.5)))
    end

    local nivel = nivelAtual()
    local ultimo_aceso = nivel > 0 and nivel or 4

    -- ---------- rotulo ----------
    local rotulo = TextWidget:new{ text = "", face = face(18), fgcolor = Blitbuffer.COLOR_BLACK }
    local function textoRotulo()
        return nivel == 0 and "Light off" or string.format("Brightness · %d of %d", nivel, NIVEIS)
    end
    rotulo:setText(textoRotulo())
    local rotulo_h = rotulo:getSize().h

    -- ---------- botoes redondos (como Noite / Girar) e trilha de segmentos ----------
    local borda = Screen:scaleBySize(2)
    local circ = Screen:scaleBySize(54)
    local gap = Screen:scaleBySize(14)
    local seg_gap = Screen:scaleBySize(5)
    local seg_h = Screen:scaleBySize(34)
    local area = inner - 2 * circ - 2 * gap
    local seg_w = math.floor((area - seg_gap * (NIVEIS - 1)) / NIVEIS)

    -- caixa com tamanho real (o FrameContainer mede pelo conteudo, nao pelo width)
    local function caixa(w, h, filho)
        return CenterContainer:new{ dimen = Geom:new{ w = w, h = h }, filho or VerticalSpan:new{ width = 0 } }
    end

    local function botaoRedondo(texto)
        return FrameContainer:new{
            padding = 0, margin = 0, bordersize = borda, color = Blitbuffer.COLOR_BLACK,
            radius = math.floor(circ / 2), background = Blitbuffer.COLOR_WHITE,
            caixa(circ - 2 * borda, circ - 2 * borda, TextWidget:new{ text = texto, face = face(26), bold = true }),
        }
    end

    local blocos = {}
    local function pintarBlocos()
        for i, b in ipairs(blocos) do
            local aceso = i <= nivel
            b.background = aceso and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
            b.color = aceso and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
        end
    end

    local trilha = HorizontalGroup:new{ align = "center" }
    for i = 1, NIVEIS do
        local b = FrameContainer:new{
            padding = 0, margin = 0, bordersize = borda, color = Blitbuffer.COLOR_DARK_GRAY,
            radius = Screen:scaleBySize(8), background = Blitbuffer.COLOR_WHITE,
            caixa(seg_w - 2 * borda, seg_h - 2 * borda),
        }
        blocos[i] = b
        table.insert(trilha, b)
        if i < NIVEIS then table.insert(trilha, HorizontalSpan:new{ width = seg_gap }) end
    end
    pintarBlocos()

    local menos = botaoRedondo("−")
    local mais = botaoRedondo("+")
    local linha = HorizontalGroup:new{ align = "center",
        menos, HorizontalSpan:new{ width = gap }, trilha, HorizontalSpan:new{ width = gap }, mais,
    }

    local grupo = VerticalGroup:new{ align = "center" }

    local function aplicar(n)
        n = math.max(0, math.min(NIVEIS, n))
        if n == 0 then
            if powerd.turnOffFrontlight then powerd:turnOffFrontlight() end
        else
            powerd:setIntensity(valorDoNivel(n))
            if powerd.isFrontlightOff and powerd:isFrontlightOff() and powerd.turnOnFrontlight then
                powerd:turnOnFrontlight()
            end
            ultimo_aceso = n
        end
        if powerd.updateResumeFrontlightState then powerd:updateResumeFrontlightState() end
        nivel = n
        pintarBlocos()
        rotulo:setText(textoRotulo())
        UIManager:setDirty(show_parent, "ui", touch_menu.dimen)
    end

    -- toque: o touch do Lev e impreciso (toques a direita caem mais para o meio), entao
    -- os segmentos sao so indicador; metade esquerda da fileira = escurecer, metade
    -- direita = clarear (inclui os botoes redondos)
    local Geom_ = Geom
    local function zona(lado)
        return setmetatable({}, { __index = function(_, k)
            if k ~= "dimen" then return nil end
            local a, b = menos.dimen, mais.dimen
            if not (a and b and a.x and b.x) then return nil end
            local meio = math.floor((a.x + b.x + b.w) / 2)
            local y, h = math.min(a.y, b.y) - Screen:scaleBySize(10), math.max(a.h, b.h) + Screen:scaleBySize(20)
            if lado == "menos" then
                return Geom_:new{ x = 0, y = y, w = meio, h = h }
            end
            return Geom_:new{ x = meio, y = y, w = Screen:getWidth() - meio, h = h }
        end })
    end
    local function escurecer() aplicar(nivel - 1) end
    local function clarear() aplicar(nivel == 0 and ultimo_aceso or nivel + 1) end
    table.insert(refs.toggles, { toggle = zona("menos"), callback = escurecer })
    table.insert(refs.toggles, { toggle = zona("mais"), callback = clarear })

    -- botoes fisicos (patch 2-botoes-lev.lua): com este painel aberto, laterais = brilho
    _G.__LEV_BRILHO = { tm = touch_menu, escurecer = escurecer, clarear = clarear }

    -- usado por outras partes do ZenOS (gestos, etc.)
    refs.setBrightness = function(valor)
        local n = (valor or 0) <= 0 and 0 or math.max(1, math.floor(valor * NIVEIS / fl_max + 0.5))
        aplicar(n)
    end

    table.insert(grupo, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(grupo, CenterContainer:new{ dimen = Geom:new{ w = inner, h = rotulo_h }, rotulo })
    table.insert(grupo, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(grupo, linha)
    table.insert(grupo, VerticalSpan:new{ width = Screen:scaleBySize(12) })
    return grupo
end

package.loaded["modules/menu/patches/brightness_slider"] = construir
logger.info("Lev: controle de brilho em blocos ativo")
