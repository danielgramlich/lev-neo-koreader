-- Lev Neo (2026-11-06): jornal da manha automatico (the news), v3.
-- * v3: ao tocar no botao the news, tenta baixar a edicao mais recente em segundo
--   plano (processo separado, sem travar a tela); avisa so se chegar edicao nova.
-- * Uma vez por dia, a partir das 6h10, fora de um livro e com Wi-Fi, baixa as
--   edicoes do feed (lista em /mnt/fat/feed_config.lua) para /mnt/fat/the news.
-- * Durante o download mostra so uma caixinha com a logo e "baixando…"
--   (os avisos do baixador de noticias ficam silenciados).
-- * Cada edicao ganha capa (logo), autor "the news", serie "the news" e titulo
--   "Manha · 6 de nov." / "Noite · 5 de nov.".
-- * Apaga as edicoes com mais de 24 h (pela data da edicao).
-- Confere ao abrir o KOReader e a cada 15 minutos; registra no crash.log ("Lev jornal:").
-- Para desfazer: apague este arquivo (koreader/patches/2-jornal-lev.lua).
local UIManager = require("ui/uimanager")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")

local INICIO = 6 * 60 + 10 -- 6h10
local PASTA = "/mnt/fat/the news"
local RECURSOS = "/mnt/fat/koreader/icons"
local LOGO = RECURSOS .. "/thenews_logo.png"
local CAPA = RECURSOS .. "/thenews_capa.png"
local MESES = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

local function hoje() return os.date("%Y-%m-%d") end

-- ---------- capa, autor e titulo das edicoes ----------
-- Nome da edicao a partir do arquivo: "AA-MM-DD_HH-MM_<titulo do feed>.epub".
-- A da manha se chama pela data ("06_11_2026" -> "06/11/2026"); a da noite, "NIGHT #344".
local function nomeEdicao(nome)
    local resto = nome:match("^%d%d%-%d%d%-%d%d_%d%d%-%d%d_(.+)%.epub$")
    if not resto then return "the news" end
    local d, m, a = resto:match("^(%d%d)_(%d%d)_(%d%d%d%d)$")
    if d then return string.format("%s/%s/%s", d, m, a) end
    return resto
end

-- Precisa marcar (ou remarcar: autor generico "the news" ou ainda com serie,
-- que o ZenOS mostra no lugar do autor)?
local function precisaMarcar(DocSettings, caminho)
    local arq = DocSettings:findCustomMetadataFile(caminho)
    if not arq then return true end
    local props = DocSettings.openSettingsFile(arq):readSetting("custom_props") or {}
    return props.authors == nil or props.authors == "the news" or props.series ~= nil
        or (props.title or ""):match("Manhã") or (props.title or ""):match("Noite") -- titulos antigos em portugues
end

local function marcarEdicoes()
    if lfs.attributes(PASTA, "mode") ~= "directory" then return 0 end
    local DocSettings = require("docsettings")
    local feitos = 0
    for nome in lfs.dir(PASTA) do
        local caminho = PASTA .. "/" .. nome
        if nome:match("%.epub$") and precisaMarcar(DocSettings, caminho) then
            local _aa, mm, dd, hh = nome:match("^(%d%d)%-(%d%d)%-(%d%d)_(%d%d)")
            local titulo = "the news"
            if dd then
                local periodo = tonumber(hh) >= 12 and "Evening" or "Morning"
                titulo = string.format("%s · %s %d", periodo, MESES[tonumber(mm)] or mm, tonumber(dd))
            end
            local edicao = nomeEdicao(nome) -- aparece no lugar do autor
            -- sem serie: com serie o ZenOS mostra "the news" no lugar do nome da edicao
            local props = { title = titulo, authors = edicao, language = "pt-BR" }
            local custom = DocSettings.openSettingsFile()
            custom.data.doc_props = props
            custom.data.custom_props = { title = titulo, authors = edicao }
            custom:flushCustomMetadata(caminho)
            if lfs.attributes(CAPA, "mode") == "file" then
                DocSettings:flushCustomCover(caminho, CAPA)
            end
            -- descarta informacoes antigas em cache (titulo/autor/capa)
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim and BookInfoManager and BookInfoManager.deleteBookInfo then
                pcall(BookInfoManager.deleteBookInfo, BookInfoManager, caminho)
            end
            feitos = feitos + 1
        end
    end
    return feitos
end

-- ---------- limpeza: edicoes com mais de 24 h ----------
-- A idade vem da data da edicao no nome do arquivo (AA-MM-DD_HH-MM_...);
-- se o nome nao tiver data, usa a data do arquivo.
local VALIDADE = 24 * 60 * 60

local function idadeEdicao(nome, caminho)
    local aa, mm, dd, hh, mi = nome:match("^(%d%d)%-(%d%d)%-(%d%d)_(%d%d)%-(%d%d)")
    local quando
    if aa then
        quando = os.time{ year = 2000 + tonumber(aa), month = tonumber(mm), day = tonumber(dd),
            hour = tonumber(hh), min = tonumber(mi), sec = 0 }
    else
        quando = lfs.attributes(caminho, "modification")
    end
    return quando and (os.time() - quando) or 0
end

local function limparAntigas()
    if lfs.attributes(PASTA, "mode") ~= "directory" then return 0 end
    local DocSettings = require("docsettings")
    local ReaderUI = require("apps/reader/readerui")
    local aberto = ReaderUI.instance and ReaderUI.instance.document and ReaderUI.instance.document.file
    -- guarda so a edicao mais recente (a de menor idade); apaga todas as outras,
    -- menos a que estiver aberta agora (essa sai na proxima limpeza)
    local edicoes = {}
    for nome in lfs.dir(PASTA) do
        if nome:match("%.epub$") and not nome:match("^%.") then
            local caminho = PASTA .. "/" .. nome
            table.insert(edicoes, { caminho = caminho, idade = idadeEdicao(nome, caminho) })
        end
    end
    table.sort(edicoes, function(a, b) return a.idade < b.idade end)
    local apagar = {}
    for i = 2, #edicoes do
        if edicoes[i].caminho ~= aberto then table.insert(apagar, edicoes[i].caminho) end
    end
    for _, caminho in ipairs(apagar) do
        pcall(function() DocSettings:open(caminho):purge() end) -- anotacoes, capa e titulo
        os.remove(caminho)
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager and BookInfoManager.deleteBookInfo then
            pcall(BookInfoManager.deleteBookInfo, BookInfoManager, caminho)
        end
        logger.info("Lev jornal: edicao antiga apagada:", caminho)
    end
    return #apagar
end

-- ---------- caixinha "baixando" com a logo ----------
local function mostrarCaixa()
    -- padrao do Lev: o mesmo modal central de carregamento (2-abrindo-lev.lua)
    local M = rawget(_G, "__LEV_MODAL")
    if M then return M.mostrar("Downloading the news…") end
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local TextWidget = require("ui/widget/textwidget")
    local Font = require("ui/font")
    local Size = require("ui/size")
    local Screen = require("device").screen
    local largura = Screen:scaleBySize(190)
    local conteudo = VerticalGroup:new{ align = "center" }
    if lfs.attributes(LOGO, "mode") == "file" then
        table.insert(conteudo, ImageWidget:new{
            file = LOGO, width = largura, height = math.floor(largura * 63 / 360), scale_factor = 0,
        })
        table.insert(conteudo, VerticalSpan:new{ width = Size.span.vertical_large })
    end
    table.insert(conteudo, TextWidget:new{ text = "Downloading…", face = Font:getFace("cfont", 16) })
    local caixa = CenterContainer:new{
        dimen = Screen:getSize(),
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.thin,
            radius = Size.radius.window,
            padding = Size.padding.large,
            conteudo,
        },
    }
    UIManager:show(caixa)
    UIManager:forceRePaint()
    return caixa
end

local function baixarSilencioso(nd)
    local Trapper = require("ui/trapper")
    local caixa = mostrarCaixa()
    Trapper:wrap(function()
        local o_info, o_confirm, o_clear, o_reset = Trapper.info, Trapper.confirm, Trapper.clear, Trapper.reset
        Trapper.info = function() return true end
        Trapper.confirm = function() return false end
        Trapper.clear = function() end
        Trapper.reset = function() end
        local ok, err = pcall(nd.loadConfigAndProcessFeeds, nd)
        Trapper.info, Trapper.confirm, Trapper.clear, Trapper.reset = o_info, o_confirm, o_clear, o_reset
        UIManager:close(caixa)
        if not ok then logger.warn("Lev jornal: erro no download:", err) end
        local n = marcarEdicoes()
        logger.info("Lev jornal: download terminado; edicoes marcadas:", n)
        pcall(limparAntigas) -- so a edicao nova fica
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance and FileManager.instance.onRefresh then
            pcall(FileManager.instance.onRefresh, FileManager.instance)
        end
        UIManager:setDirty(nil, "full")
    end)
end

-- ---------- quando baixar ----------
-- Wi-Fi com endereco IP? (o estado interno do KOReader pode estar desatualizado
-- logo apos reiniciar, entao tambem conferimos a interface direto)
local function temRede(NetworkMgr)
    local ok, conectado = pcall(NetworkMgr.isConnected, NetworkMgr)
    if ok and conectado then return true end
    local p = io.popen("ifconfig wlan0 2>/dev/null")
    if not p then return false end
    local s = p:read("*a") or ""
    p:close()
    return s:match("inet addr:%d") ~= nil
end

-- ---------- download em segundo plano (botao the news) ----------
-- Roda o baixador num processo separado (fork): a tela continua livre (lendo a
-- edicao que ja existe). No fim, marca capa/titulo e avisa se chegou edicao nova.
local fundo = { pid = nil }

local function pegarBaixador()
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    local ok_pl, PluginLoader = pcall(require, "pluginloader")
    local nd = (fm and fm.newsdownloader)
        or (ok_pl and PluginLoader.getPluginInstance and PluginLoader:getPluginInstance("newsdownloader"))
    if not nd or not nd.loadConfigAndProcessFeeds then return nil end
    if nd.lazyInitialization then nd:lazyInitialization() end
    if not nd.feed_config_path then return nil end
    return nd
end

local function edicoesAtuais()
    local t = {}
    if lfs.attributes(PASTA, "mode") == "directory" then
        for nome in lfs.dir(PASTA) do
            if nome:match("%.epub$") then t[nome] = true end
        end
    end
    return t
end

local function baixarEmSegundoPlano()
    if fundo.pid then return "ja baixando" end
    local NetworkMgr = require("ui/network/manager")
    if not temRede(NetworkMgr) then return "sem Wi-Fi" end
    local nd = pegarBaixador()
    if not nd then return "plugin de noticias nao encontrado" end
    local ffiutil = require("ffi/util")
    local antes = edicoesAtuais()
    local pid = ffiutil.runInSubProcess(function()
        -- processo filho: nada de desenhar na tela
        local nada = function() end
        UIManager.show, UIManager.forceRePaint, UIManager.setDirty = nada, nada, nada
        pcall(nd.loadConfigAndProcessFeeds, nd)
    end)
    if not pid then return "nao consegui iniciar o download" end
    fundo.pid, fundo.inicio = pid, os.time()
    local function conferir()
        if not fundo.pid then return end
        if not ffiutil.isSubProcessDone(fundo.pid) then
            if os.time() - fundo.inicio > 240 then -- 4 min: desiste
                pcall(ffiutil.terminateSubProcess, fundo.pid)
                logger.warn("Lev jornal: download em segundo plano demorou demais; cancelado")
                fundo.pid = nil
            else
                UIManager:scheduleIn(3, conferir)
            end
            return
        end
        fundo.pid = nil
        local ok_m, n = pcall(marcarEdicoes)
        local novas = 0
        for nome in pairs(edicoesAtuais()) do
            if not antes[nome] then novas = novas + 1 end
        end
        logger.info("Lev jornal: segundo plano terminou; novas:", novas, "marcadas:", ok_m and n or n)
        if novas > 0 then
            pcall(limparAntigas) -- so a edicao nova fica
            G_reader_settings:saveSetting("lev_jornal_ultimo", hoje())
            local FileManager = require("apps/filemanager/filemanager")
            if FileManager.instance and FileManager.instance.onRefresh then
                pcall(FileManager.instance.onRefresh, FileManager.instance)
            end
            local ok_n, Notification = pcall(require, "ui/widget/notification")
            if ok_n and Notification then
                Notification:notify("New the news edition available", Notification.SOURCE_ALWAYS_SHOW)
            end
        end
    end
    UIManager:scheduleIn(3, conferir)
    return "baixando em segundo plano"
end

-- usado pelo botao the news (patch 2-ajustes-lev.lua)
_G.__LEV_JORNAL_SEGUNDO_PLANO = function()
    local ok, motivo = pcall(baixarEmSegundoPlano)
    logger.info("Lev jornal (botao):", ok and motivo or ("erro: " .. tostring(motivo)))
end

local function verificar()
    if G_reader_settings:readSetting("lev_jornal_ultimo") == hoje() then
        return "ja baixado hoje"
    end
    local t = os.date("*t")
    if t.hour * 60 + t.min < INICIO then return "antes das 6h10" end
    local NetworkMgr = require("ui/network/manager")
    if not temRede(NetworkMgr) then return "sem Wi-Fi" end
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI.instance then return "livro aberto" end
    local FileManager = require("apps/filemanager/filemanager")
    local fm = FileManager.instance
    if not fm then return "biblioteca nao carregada" end
    -- o KOReader registra o plugin pelo nome da pasta (newsdownloader.koplugin)
    local ok_pl, PluginLoader = pcall(require, "pluginloader")
    local nd = fm.newsdownloader
        or (ok_pl and PluginLoader.getPluginInstance and PluginLoader:getPluginInstance("newsdownloader"))
    if not nd or not nd.loadConfigAndProcessFeeds then
        return "plugin de noticias nao encontrado"
    end
    -- o plugin so define a pasta e o feed_config.lua na inicializacao "preguicosa",
    -- que normalmente roda ao abrir o menu dele; sem isso o caminho fica vazio
    if nd.lazyInitialization then nd:lazyInitialization() end
    if not nd.feed_config_path then return "plugin de noticias sem configuracao" end
    G_reader_settings:saveSetting("lev_jornal_ultimo", hoje())
    baixarSilencioso(nd)
    return "baixando o jornal do dia"
end

local function ciclo()
    local ok_l, n_l = pcall(limparAntigas)
    if not ok_l then logger.warn("Lev jornal: erro na limpeza:", n_l) end
    local ok, motivo = pcall(verificar)
    logger.info("Lev jornal:", ok and motivo or ("erro: " .. tostring(motivo)))
    UIManager:scheduleIn(15 * 60, ciclo)
end

-- edicoes ja baixadas (ou copiadas) sem capa/autor: marca ao iniciar
UIManager:scheduleIn(20, function()
    local ok, n = pcall(marcarEdicoes)
    if ok and n > 0 then
        logger.info("Lev jornal: edicoes marcadas ao iniciar:", n)
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance and FileManager.instance.onRefresh then
            pcall(FileManager.instance.onRefresh, FileManager.instance)
        end
    elseif not ok then
        logger.warn("Lev jornal: erro ao marcar edicoes:", n)
    end
end)
UIManager:scheduleIn(40, ciclo)
logger.info("Lev: jornal automatico ativo (v3)")
