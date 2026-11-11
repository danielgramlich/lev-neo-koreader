-- Lev Neo (2026-11-11, v2): topo do Inicio igual ao do menu de acesso rapido.
-- * Hora, Wi-Fi e bateria aparecem uma vez so, no topo do Inicio, desenhados com a mesma
--   funcao e as mesmas opcoes do menu (buildStatusRow, padding 6, fonte x_smallinfofont) e
--   na mesma posicao: abrir o menu nao "mexe" essa linha (consistencia). O cartao do livro
--   atual nao mostra mais a propria barra (featured.show_status_bar = false em home.lua).
-- * A tela tem uma linha morta perto do topo (y ~41): ela fica sob essa linha de status,
--   como no menu.
-- * A linha e redesenhada a cada minuto (hora; Wi-Fi e bateria junto).
-- Como: o corpo do Inicio e montado pelo ZenOS em StandalonePage.mount_body; o conteudo
-- desce DESCER px e a linha de status fica por cima, no espaco livre do topo.
-- Para desfazer: apague este arquivo (e volte home.lua: show_status_bar).
local userpatch = require("userpatch")
local logger = require("logger")

-- posicao calibrada pela captura do menu (linha do menu: hora em x 16-75, y 22-38)
local XOFF, YTOP = 9, 10
local FOLGA = 4 -- espaco entre a linha de status e o conteudo

local zenPlugin -- o KOReader entrega o plugin a funcao abaixo; o global do ZenOS so existe por instantes
userpatch.registerPatchPluginFunc("zenos", function(plugin)
    zenPlugin = plugin or zenPlugin
    local ok, Pagina = pcall(require, "modules/filebrowser/patches/standalone_page")
    if not ok or type(Pagina) ~= "table" or type(Pagina.mount_body) ~= "function" then
        logger.warn("Lev inicio: montagem de pagina do ZenOS nao encontrada")
        return
    end
    if Pagina._lev_topo then return end
    Pagina._lev_topo = true
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Screen = require("device").screen

    local avisou = false
    local function construtor()
        local okS, SS = pcall(require, "common/shared_state")
        local plugin = zenPlugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local okG, f = false, nil
        if okS and plugin then okG, f = pcall(SS.get, plugin, "buildStatusRow") end
        if type(f) ~= "function" and not avisou then
            avisou = true
            logger.warn("Lev inicio: buildStatusRow indisponivel:", okS, plugin ~= nil, okG, type(f))
        end
        return type(f) == "function" and f or nil
    end
    -- se o Inicio foi montado antes do ZenOS registrar a funcao, remonta quando ela existir
    local function remontarQuandoPronto(n)
        if construtor() then
            local carregado = package.loaded["modules/filebrowser/patches/home_page"]
            local Home = carregado
            if type(carregado) == "function" then
                local reg = userpatch.getUpValue(carregado, "register_home_api")
                Home = type(reg) == "function" and userpatch.getUpValue(reg, "M") or nil
            end
            if type(Home) == "table" and Home.rebuildActive then pcall(Home.rebuildActive) end
            logger.info("Lev inicio: Inicio remontado com a linha de status")
        elseif n < 30 then
            UIManager:scheduleIn(2, function() remontarQuandoPronto(n + 1) end)
        end
    end
    local function linhaStatus()
        local f = construtor()
        if not f then return nil end
        local okL, w = pcall(f, Screen:getWidth() - 2 * XOFF, { padding = 6, font_name = "x_smallinfofont" })
        return okL and w or nil
    end

    local original = Pagina.mount_body
    Pagina.mount_body = function(menu, conteudo, ...)
        -- so o Inicio marca _zen_home_page_padding no menu antes de montar
        if not (type(menu) == "table" and menu._zen_home_page_padding ~= nil and type(conteudo) == "table") then
            return original(menu, conteudo, ...)
        end
        local linha = linhaStatus()
        if not linha then
            if not menu._lev_remontar then
                menu._lev_remontar = true
                UIManager:scheduleIn(2, function() remontarQuandoPronto(0) end)
            end
            conteudo = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = 18 }, conteudo }
            return original(menu, conteudo, ...)
        end
        local alturaLinha = linha:getSize().h
        local topoConteudo = tonumber(menu._zen_home_page_padding) or 4
        -- o conteudo do ZenOS ja comeca com um respiro; desce so o que falta para caber a linha
        local descer = math.max(0, YTOP + alturaLinha + FOLGA - topoConteudo - 19)
        local caixaLinha = HorizontalGroup:new{ HorizontalSpan:new{ width = XOFF }, linha }
        local corpo = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = descer }, conteudo }
        local topo = VerticalGroup:new{ align = "left", VerticalSpan:new{ width = YTOP }, caixaLinha }
        local junto = OverlapGroup:new{
            dimen = Geom:new{ w = Screen:getWidth(), h = corpo:getSize().h },
            corpo, topo,
        }
        -- hora atualizada a cada minuto (sempre na linha da montagem mais recente)
        menu._lev_caixa_status = caixaLinha
        local function atualizar()
            if not menu._lev_status_vivo then return end
            local caixa = menu._lev_caixa_status
            local nova = caixa and linhaStatus()
            if nova then
                caixa[2] = nova
                if caixa.resetLayout then caixa:resetLayout() end
                local naTela = false
                for _, j in ipairs(UIManager._window_stack or {}) do
                    if j.widget == menu then naTela = true break end
                end
                if naTela then
                    UIManager:setDirty(menu, "ui", Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = YTOP + alturaLinha })
                end
            end
            UIManager:scheduleIn(60 - (os.time() % 60) + 1, atualizar)
        end
        if not menu._lev_status_vivo then
            menu._lev_status_vivo = true
            UIManager:scheduleIn(60 - (os.time() % 60) + 1, atualizar)
        end
        return original(menu, junto, ...)
    end
    logger.info("Lev: Inicio com a linha de status do menu")
end)
