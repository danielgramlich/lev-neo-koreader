-- Lev Neo (2026-11-06; v4 2026-11-11): the news automatico.
-- * Todo toque na aba the news procura e baixa a edicao mais recente em segundo plano;
--   avisa so se chegar edicao nova.
-- * Alem disso, de hora em hora a partir das 6h10 (com Wi-Fi) procura sozinho, o que
--   pega as edicoes da manha e da noite. Feed em /mnt/fat/feed_config.lua.
-- * v4: o download roda no baixador leve koreader/lev_baixar_jornal.lua (processo novo,
--   ~90 MB), e nao mais num fork do KOReader, que estourava a memoria em edicoes grandes.
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

-- ---------- download em segundo plano ----------
-- Roda o baixador leve (koreader/lev_baixar_jornal.lua) como processo novo, sem copiar o
-- KOReader inteiro: o fork antigo (~220 MB) era morto por falta de memoria em edicoes
-- grandes e deixava o .epub.tmp pela metade. A tela continua livre; no fim, marca
-- capa/titulo, guarda so a edicao mais nova e avisa se chegou edicao nova.
local BAIXADOR = "/mnt/fat/koreader/lev_baixar_jornal.lua"
local FEITO = "/tmp/lev_jornal.feito"
local SAIDA = "/tmp/lev_jornal.log"
local LIMITE = 6 * 60 -- segundos ate desistir
local fundo = { ativo = false }

local function edicoesAtuais()
    local t = {}
    if lfs.attributes(PASTA, "mode") == "directory" then
        for nome in lfs.dir(PASTA) do
            if nome:match("%.epub$") then t[nome] = true end
        end
    end
    return t
end

local function limparTemporarios()
    if lfs.attributes(PASTA, "mode") ~= "directory" then return end
    for nome in lfs.dir(PASTA) do
        if nome:match("%.tmp$") then os.remove(PASTA .. "/" .. nome) end
    end
end

local function edicaoMaisNova()
    local melhor, idade
    for nome in pairs(edicoesAtuais()) do
        local caminho = PASTA .. "/" .. nome
        local i = idadeEdicao(nome, caminho)
        if not idade or i < idade then melhor, idade = caminho, i end
    end
    return melhor
end

local function pararBaixador()
    os.execute("for p in ; do kill ; done")
end

local function baixarEmSegundoPlano()
    if fundo.ativo then return "ja baixando" end
    local NetworkMgr = require("ui/network/manager")
    if not temRede(NetworkMgr) then return "sem Wi-Fi" end
    if lfs.attributes(BAIXADOR, "mode") ~= "file" then return "baixador nao encontrado" end
    limparTemporarios()
    local antes = edicoesAtuais()
    os.remove(FEITO)
    G_reader_settings:saveSetting("lev_jornal_ultima_busca", os.time())
    os.execute(string.format(
        "cd /mnt/fat/koreader && (./luajit %s /mnt/fat/ /mnt/fat/feed_config.lua > %s 2>&1; echo 0 > %s) &",
        BAIXADOR, SAIDA, FEITO))
    fundo.ativo, fundo.inicio = true, os.time()
    local function conferir()
        if not fundo.ativo then return end
        if lfs.attributes(FEITO, "mode") ~= "file" then
            if os.time() - fundo.inicio > LIMITE then
                pararBaixador()
                limparTemporarios()
                fundo.ativo = false
                logger.warn("Lev jornal: download demorou demais; cancelado")
            else
                UIManager:scheduleIn(3, conferir)
            end
            return
        end
        fundo.ativo = false
        local f = io.open(FEITO); local codigo = f and f:read("*l"); if f then f:close() end
        local ok_m, n = pcall(marcarEdicoes)
        local novas = 0
        for nome in pairs(edicoesAtuais()) do
            if not antes[nome] then novas = novas + 1 end
        end
        logger.info("Lev jornal: segundo plano terminou; codigo:", codigo, "novas:", novas, "marcadas:", ok_m and n or n)
        if novas > 0 then
            pcall(limparAntigas) -- so a edicao nova fica
            G_reader_settings:saveSetting("lev_jornal_ultimo", hoje())
            local FileManager = require("apps/filemanager/filemanager")
            if FileManager.instance and FileManager.instance.onRefresh then
                pcall(FileManager.instance.onRefresh, FileManager.instance)
            end
            -- lendo a edicao antiga agora? pergunta se quer abrir a nova (troca na hora)
            local ReaderUI = require("apps/reader/readerui")
            local leitor = ReaderUI.instance
            local aberto = leitor and leitor.document and leitor.document.file
            local nova = edicaoMaisNova()
            if aberto and nova and aberto ~= nova and aberto:sub(1, #PASTA) == PASTA then
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:show(ConfirmBox:new{
                    text = "A new edition of the news is ready.",
                    ok_text = "Open", cancel_text = "Later",
                    ok_callback = function()
                        if ReaderUI.instance then ReaderUI.instance:switchDocument(nova) end
                        UIManager:scheduleIn(8, function() pcall(limparAntigas) end)
                    end,
                })
            else
                local ok_n, Notification = pcall(require, "ui/widget/notification")
                if ok_n and Notification then
                    Notification:notify("New the news edition available", Notification.SOURCE_ALWAYS_SHOW)
                end
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
    local ultima = tonumber(G_reader_settings:readSetting("lev_jornal_ultima_busca")) or 0
    if os.time() - ultima < 60 * 60 then return "buscou ha menos de 1 h" end
    local t = os.date("*t")
    if t.hour * 60 + t.min < INICIO then return "antes das 6h10" end
    return baixarEmSegundoPlano()
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
logger.info("Lev: jornal automatico ativo (v4)")
