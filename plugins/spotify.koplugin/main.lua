--[[
Spotify para o Lev Neo (2026-11-06): controle remoto via Spotify Web API (Spotify Connect).
O Lev nao toca audio; ele controla o Spotify nos seus aparelhos (celular, Mac, Echo...).
Credenciais em settings/spotify.lua: client_id e refresh_token (OAuth PKCE, sem client secret),
geradas uma vez no Mac (autorizar_spotify.py). Requer Spotify Premium e Wi-Fi.

v3: tela clara no estilo do ZenOS, acima da barra inferior (que continua visivel e
funcionando). "Tocando agora": capa, musica, artista e controles, sem barra de progresso;
confere o Spotify a cada 30 s em silencio e so redesenha se a musica/estado mudar.
"Biblioteca": Musicas Curtidas, Playlists e Albuns (toca o item escolhido).
Botoes fisicos (patch 2-botoes-lev.lua):
  tocando:    laterais = musica anterior/seguinte; direita segurada = tocar/pausar;
              esquerda segurada = sair
  biblioteca: laterais = sobe/desce; direita segurada = abrir/tocar; esquerda segurada = voltar
]]
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local ffiutil = require("ffi/util")
local logger = require("logger")

local Screen = Device.screen
local API = "https://api.spotify.com/v1"
local TOKEN_URL = "https://accounts.spotify.com/api/token"
local ICONES = DataStorage:getDataDir() .. "/icons"
local CAPA_TMP = "/tmp/spotify_capa.jpg"
local PRETO, BRANCO = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local CINZA = Blitbuffer.COLOR_LIGHT_GRAY

-- ---------- rede ----------
local function urlencode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function requisicao(metodo, url, corpo, cabecalhos, sink)
    local http = require("socket.http")
    local ltn12 = require("ltn12")
    local socketutil = require("socketutil")
    local saida = {}
    cabecalhos = cabecalhos or {}
    cabecalhos["Content-Length"] = tostring(corpo and #corpo or 0)
    socketutil:set_timeout(8, 15)
    local ok, r1, codigo = pcall(http.request, {
        url = url,
        method = metodo,
        headers = cabecalhos,
        source = corpo and ltn12.source.string(corpo) or nil,
        sink = sink or ltn12.sink.table(saida),
    })
    socketutil:reset_timeout()
    if not ok then return nil, tostring(r1) end
    if r1 == nil then return nil, tostring(codigo) end
    return tonumber(codigo), table.concat(saida)
end

local function mmss(ms)
    if not ms then return "" end
    local s = math.floor(ms / 1000)
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

-- ---------- plugin ----------
local Spotify = WidgetContainer:extend{
    name = "spotify",
    is_doc_only = false,
}

function Spotify:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/spotify.lua")
    self.token, self.expira = nil, 0
    self.ui.menu:registerToMainMenu(self)
    Dispatcher:registerAction("spotify_painel", {
        category = "none", event = "SpotifyPainel", title = "Spotify: open", general = true,
    })
    Dispatcher:registerAction("spotify_tocar_pausar", {
        category = "none", event = "SpotifyTocarPausar", title = "Spotify: play/pause", general = true,
    })
    Dispatcher:registerAction("spotify_proxima", {
        category = "none", event = "SpotifyProxima", title = "Spotify: next track", general = true,
    })
end

function Spotify:addToMainMenu(menu_items)
    menu_items.spotify = {
        text = "Spotify",
        sorting_hint = "tools",
        callback = function() self:abrirPainel() end,
    }
end

function Spotify:onSpotifyPainel() self:abrirPainel() return true end
function Spotify:onSpotifyTocarPausar() self:acao("tocar_pausar") return true end
function Spotify:onSpotifyProxima() self:acao("proxima") return true end

function Spotify:tokenAcesso(forcar)
    if not forcar and self.token and os.time() < self.expira - 60 then return self.token end
    local client_id = self.settings:readSetting("client_id")
    local refresh = self.settings:readSetting("refresh_token")
    if not client_id or not refresh then return nil, "Spotify is not set up on this device." end
    local corpo = "grant_type=refresh_token&refresh_token=" .. urlencode(refresh) .. "&client_id=" .. urlencode(client_id)
    local codigo, resp = requisicao("POST", TOKEN_URL, corpo, { ["Content-Type"] = "application/x-www-form-urlencoded" })
    if codigo ~= 200 then
        logger.warn("Spotify: falha ao renovar acesso", codigo, resp)
        return nil, codigo and ("O Spotify recusou o acesso (" .. codigo .. "). Pode ser preciso autorizar de novo.")
            or "Can't reach Spotify. Is Wi-Fi on?"
    end
    local dados = require("json").decode(resp)
    self.token = dados.access_token
    self.expira = os.time() + (tonumber(dados.expires_in) or 3600)
    if dados.refresh_token and dados.refresh_token ~= refresh then
        self.settings:saveSetting("refresh_token", dados.refresh_token)
        self.settings:flush()
    end
    return self.token
end

-- chamada a API com renovacao automatica (uma nova tentativa em caso de 401)
function Spotify:api(metodo, caminho, corpo_tabela)
    for tentativa = 1, 2 do
        local token, erro = self:tokenAcesso(tentativa == 2)
        if not token then return nil, erro end
        local corpo = corpo_tabela and require("json").encode(corpo_tabela) or nil
        local codigo, resp = requisicao(metodo, API .. caminho, corpo, {
            ["Authorization"] = "Bearer " .. token,
            ["Content-Type"] = corpo and "application/json" or nil,
        })
        if codigo ~= 401 then
            if not codigo then return nil, "Can't reach Spotify. Is Wi-Fi on?" end
            if codigo == 204 or resp == "" then return codigo, nil end
            local ok, dados = pcall(require("json").decode, resp)
            return codigo, ok and dados or nil
        end
    end
    return nil, "Spotify refused access."
end

function Spotify:estado()
    local codigo, dados = self:api("GET", "/me/player")
    if not codigo then return nil, dados end
    if codigo == 204 or not dados then return { ativo = false } end
    local item = dados.item or {}
    local artistas = {}
    for _, a in ipairs(item.artists or {}) do table.insert(artistas, a.name) end
    local capa_url
    local imagens = item.album and item.album.images or {}
    for _, im in ipairs(imagens) do -- prefere a de ~300 px
        if not capa_url or (im.width and im.width >= 250 and im.width <= 400) then capa_url = im.url end
    end
    if dados.device and dados.device.id then self:lembrarAparelho(dados.device.id, dados.device.name) end
    return {
        ativo = true,
        tocando = dados.is_playing,
        musica = item.name,
        artista = table.concat(artistas, ", "),
        album = item.album and item.album.name,
        aparelho = dados.device and dados.device.name,
        aparelho_id = dados.device and dados.device.id,
        volume = dados.device and dados.device.volume_percent,
        progresso = dados.progress_ms,
        duracao = item.duration_ms,
        capa_url = capa_url,
        lido_em = os.time(),
    }
end

-- baixa a capa do album (cache pela URL)
-- Cada capa ganha um arquivo proprio (pelo id da imagem): o KOReader guarda imagens
-- em cache pelo caminho, entao reaproveitar o mesmo nome mostraria sempre a capa antiga.
function Spotify:capa(url)
    if not url then return nil end
    local id = (url:match("([%w]+)$") or tostring(#url)):sub(-40)
    local arq = CAPA_TMP:gsub("%.jpg$", "_" .. id .. ".jpg")
    if lfs.attributes(arq, "mode") == "file" then return arq end
    local f = io.open(arq, "wb")
    if not f then return nil end
    local codigo = requisicao("GET", url, nil, {}, require("ltn12").sink.file(f))
    if codigo == 200 then
        if self.capa_arq and self.capa_arq ~= arq then os.remove(self.capa_arq) end
        self.capa_arq = arq
        return arq
    end
    os.remove(arq)
    return nil
end

-- ---------- onde tocar ----------
-- Guarda o ultimo aparelho que tocou, para retomar nele sem perguntar.
function Spotify:lembrarAparelho(id, nome)
    if not id or self.settings:readSetting("ultimo_aparelho") == id then return end
    self.settings:saveSetting("ultimo_aparelho", id)
    self.settings:saveSetting("ultimo_aparelho_nome", nome)
    self.settings:flush()
end

function Spotify:aparelhos()
    local codigo, dados = self:api("GET", "/me/player/devices")
    if not codigo or type(dados) ~= "table" or type(dados.devices) ~= "table" then return nil end
    return dados.devices
end

-- Sem nenhum aparelho ativo: o ultimo usado (se estiver disponivel) ou o unico da lista.
-- Devolve id, nome; ou nil + lista quando ha mais de uma opcao e nenhuma lembrada.
function Spotify:aparelhoAutomatico()
    local lista = self:aparelhos()
    if not lista or #lista == 0 then return nil, lista end
    local ultimo = self.settings:readSetting("ultimo_aparelho")
    local ultimo_nome = self.settings:readSetting("ultimo_aparelho_nome")
    for _, d in ipairs(lista) do
        if d.is_active then return d.id, d.name end
    end
    for _, d in ipairs(lista) do
        if ultimo and d.id == ultimo then return d.id, d.name end
    end
    for _, d in ipairs(lista) do -- o id pode mudar; o nome costuma ficar
        if ultimo_nome and d.name == ultimo_nome then return d.id, d.name end
    end
    if #lista == 1 then return lista[1].id, lista[1].name end
    return nil, lista
end

-- executa a acao ja num aparelho especifico (depois de escolher onde tocar)
function Spotify:acaoEm(aparelho, qual, arg)
    local codigo, erro
    if qual == "tocar_contexto" then
        codigo, erro = self:api("PUT", "/me/player/play?device_id=" .. urlencode(aparelho), { context_uri = arg })
    else
        codigo, erro = self:api("PUT", "/me/player", { device_ids = { aparelho }, play = true })
        if codigo and codigo < 400 and (qual == "proxima" or qual == "anterior") then
            ffiutil.sleep(1)
            codigo, erro = self:api("POST", "/me/player/" .. (qual == "proxima" and "next" or "previous"))
        end
    end
    if codigo and codigo < 400 then self:lembrarAparelho(aparelho) end
    return codigo, erro
end

-- Devolve true (feito), false (erro ja avisado) ou "escolher" (precisa escolher onde tocar).
function Spotify:acao(qual, arg)
    local codigo, erro
    if qual == "tocar_pausar" then
        local st = self:estado()
        if st and st.tocando then codigo, erro = self:api("PUT", "/me/player/pause")
        else codigo, erro = self:api("PUT", "/me/player/play") end
    elseif qual == "proxima" then codigo, erro = self:api("POST", "/me/player/next")
    elseif qual == "anterior" then codigo, erro = self:api("POST", "/me/player/previous")
    elseif qual == "volume" then
        codigo, erro = self:api("PUT", "/me/player/volume?volume_percent=" .. math.max(0, math.min(100, arg)))
    elseif qual == "transferir" then
        codigo, erro = self:api("PUT", "/me/player", { device_ids = { arg }, play = true })
        if codigo and codigo < 400 then self:lembrarAparelho(arg) end
    elseif qual == "tocar_contexto" then -- playlist, album ou curtidas (context_uri)
        codigo, erro = self:api("PUT", "/me/player/play", { context_uri = arg })
    end
    -- 404 = nenhum aparelho ativo: tenta tocar sozinho no ultimo/unico aparelho
    if codigo == 404 and qual ~= "transferir" and qual ~= "volume" then
        local id, lista = self:aparelhoAutomatico()
        if id then
            codigo, erro = self:acaoEm(id, qual, arg)
        elseif lista and #lista > 1 then
            return "escolher"
        else
            UIManager:show(InfoMessage:new{
                text = "No Spotify device found. Open Spotify on your phone or Mac, or ask Alexa.",
                timeout = 5 })
            return false
        end
    end
    if codigo and codigo >= 400 then
        local msg = type(erro) == "table" and erro.error and erro.error.message or tostring(codigo)
        if codigo == 404 then msg = "That device didn't respond. Pick another one in \"Play on…\"." end
        if codigo == 403 then msg = "Spotify didn't allow it: " .. msg end
        UIManager:show(InfoMessage:new{ text = msg, timeout = 4 })
        return false
    elseif not codigo then
        UIManager:show(InfoMessage:new{ text = tostring(erro), timeout = 4 })
        return false
    end
    return true
end

-- ---------- biblioteca ----------
function Spotify:usuario()
    if self.uid then return self.uid end
    local codigo, dados = self:api("GET", "/me")
    if codigo == 200 and dados and dados.id then self.uid = dados.id end
    return self.uid
end

-- busca ate `max` itens de um endpoint paginado (limit 50)
function Spotify:listar(caminho, max)
    local itens, offset = {}, 0
    max = max or 150
    while #itens < max do
        local sep = caminho:find("?", 1, true) and "&" or "?"
        local codigo, dados = self:api("GET", caminho .. sep .. "limit=50&offset=" .. offset)
        if codigo ~= 200 or not dados or not dados.items then
            return #itens > 0 and itens or nil, (type(dados) == "table" and dados.error and dados.error.message) or codigo
        end
        for _, it in ipairs(dados.items) do table.insert(itens, it) end
        if not dados.next or #dados.items == 0 then break end
        offset = offset + 50
    end
    return itens
end

-- ---------- tela clara (estilo ZenOS), com a barra inferior do ZenOS visivel ----------
-- Ocupa so a area acima da barra; um toque na barra fecha esta tela e vai para a aba tocada.
local Event = require("ui/event")
local VERIFICAR_S = 30 -- consulta silenciosa; so redesenha se a musica/estado mudar
local ESCURO = Blitbuffer.COLOR_DARK_GRAY
local LINHA_COR = Blitbuffer.COLOR_LIGHT_GRAY

local TelaSpotify = InputContainer:extend{
    plugin = nil,
    covers_fullscreen = false, -- deixa a barra do ZenOS (embaixo) aparecer
    _lev_spotify = true, -- reconhecida pelo patch de botoes
}

local function alturaBarra()
    local h = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
    if h <= 0 or h > Screen:getHeight() / 3 then h = 0 end
    return h
end

local function texto(t, tam, cor, negrito)
    return TextWidget:new{ text = t or "", face = Font:getFace("cfont", tam), fgcolor = cor or PRETO, bold = negrito }
end

local function caixaTexto(t, tam, cor, largura, negrito, alinhamento, fundo, max_linhas)
    local face = Font:getFace("cfont", tam)
    return TextBoxWidget:new{
        text = t or "", face = face, fgcolor = cor or PRETO, bgcolor = fundo or BRANCO,
        width = largura, alignment = alinhamento or "center", bold = negrito,
        height = max_linhas and math.floor(max_linhas * face.size * 1.45) or nil,
        height_adjust = max_linhas and true or nil,
        height_overflow_show_ellipsis = max_linhas and true or nil,
    }
end

function TelaSpotify:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    self.altura_barra = alturaBarra()
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H - self.altura_barra }
    -- toques na tela inteira (inclusive na barra, que repassamos ao ZenOS)
    self.ges_events.TapTela = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
    self.key_events.Fechar = { { "Back" } }
    self.modo = "tocando"
    self.pilha = {}
    self:montar()
end

function TelaSpotify:alvo(widget, acao)
    local f = FrameContainer:new{ bordersize = 0, padding = Screen:scaleBySize(6), background = BRANCO, widget }
    table.insert(self.alvos, { w = f, acao = acao })
    return f
end

function TelaSpotify:pilula(rotulo, acao)
    local f = FrameContainer:new{
        bordersize = Screen:scaleBySize(1), color = PRETO, background = BRANCO,
        radius = Screen:scaleBySize(18), padding = Screen:scaleBySize(8),
        padding_left = Screen:scaleBySize(18), padding_right = Screen:scaleBySize(18),
        texto(rotulo, 16, PRETO),
    }
    table.insert(self.alvos, { w = f, acao = acao })
    return f
end

-- titulo grande a esquerda, como as telas do ZenOS
function TelaSpotify:cabecalho(W, titulo, subtitulo)
    local margem = Screen:scaleBySize(28)
    local linha = HorizontalGroup:new{ align = "center" }
    local logo = ICONES .. "/spotify_lev.png"
    if lfs.attributes(logo, "mode") == "file" then
        table.insert(linha, ImageWidget:new{ file = logo, width = Screen:scaleBySize(34), height = Screen:scaleBySize(34), scale_factor = 0 })
        table.insert(linha, HorizontalSpan:new{ width = Screen:scaleBySize(12) })
    end
    table.insert(linha, texto(titulo, 26, PRETO, true))
    local g = VerticalGroup:new{ align = "left", linha }
    if subtitulo and subtitulo ~= "" then
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
        table.insert(g, texto(subtitulo, 14, ESCURO))
    end
    return FrameContainer:new{
        width = W, bordersize = 0, background = BRANCO,
        padding = 0, padding_left = margem, padding_top = Screen:scaleBySize(22), padding_bottom = Screen:scaleBySize(14),
        g,
    }
end

-- ---------- modo "tocando agora" ----------
function TelaSpotify:montarTocando(W, H)
    local st, erro = self.plugin:estado()
    self.st = st
    local topo = self:cabecalho(W, "Spotify", st and st.aparelho and ("playing on " .. st.aparelho) or nil)
    local g = VerticalGroup:new{ align = "center" }

    -- capa do album
    local lado = math.max(Screen:scaleBySize(140), math.min(math.floor(W * 0.56), H - Screen:scaleBySize(560)))
    local arq = st and st.ativo and self.plugin:capa(st.capa_url)
    if arq then
        table.insert(g, FrameContainer:new{ bordersize = Screen:scaleBySize(1), color = LINHA_COR, padding = 0,
            ImageWidget:new{ file = arq, width = lado, height = lado, scale_factor = 0 } })
    else
        table.insert(g, FrameContainer:new{
            width = lado, height = lado, bordersize = Screen:scaleBySize(1), color = LINHA_COR, background = BRANCO,
            radius = Screen:scaleBySize(10), padding = 0,
            CenterContainer:new{ dimen = Geom:new{ w = lado - 2, h = lado - 2 }, texto("♪", 60, LINHA_COR) },
        })
    end
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(22) })

    -- musica e artista
    local largura_texto = W - Screen:scaleBySize(80)
    if not st then
        table.insert(g, caixaTexto(tostring(erro), 18, PRETO, largura_texto, false, nil, nil, 3))
    elseif not st.ativo then
        table.insert(g, caixaTexto("Nothing playing", 24, PRETO, largura_texto, true))
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(8) })
        table.insert(g, caixaTexto("Pick something in Library or a device in “Play on…”", 16, ESCURO, largura_texto))
    else
        table.insert(g, caixaTexto(st.musica or "—", 24, PRETO, largura_texto, true, nil, nil, 2))
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        table.insert(g, caixaTexto(st.artista or "", 18, ESCURO, largura_texto, false, nil, nil, 1))
    end
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(26) })

    -- controles
    local function icone(nome, lado_px)
        return ImageWidget:new{ file = ICONES .. "/" .. nome, width = lado_px, height = lado_px, scale_factor = 0 }
    end
    local pequeno, grande = Screen:scaleBySize(52), Screen:scaleBySize(80)
    local tocando = st and st.tocando
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:alvo(icone("sp_anterior_claro.png", pequeno), function() self:executar("anterior") end),
        HorizontalSpan:new{ width = Screen:scaleBySize(40) },
        self:alvo(icone(tocando and "sp_pausar_claro.png" or "sp_tocar_claro.png", grande), function() self:executar("tocar_pausar") end),
        HorizontalSpan:new{ width = Screen:scaleBySize(40) },
        self:alvo(icone("sp_proxima_claro.png", pequeno), function() self:executar("proxima") end),
    })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(22) })
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:pilula("Library", function() self:abrirBiblioteca() end),
        HorizontalSpan:new{ width = Screen:scaleBySize(12) },
        self:pilula("Play on…", function() self:escolherAparelho() end),
    })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    local vol = st and st.volume or 50
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:pilula("−  volume", function() self:executar("volume", vol - 10) end),
        HorizontalSpan:new{ width = Screen:scaleBySize(12) },
        self:pilula("volume  +", function() self:executar("volume", vol + 10) end),
    })

    local h_topo = topo:getSize().h
    return VerticalGroup:new{ align = "left",
        topo,
        CenterContainer:new{ dimen = Geom:new{ w = W, h = H - h_topo }, g },
    }
end

-- ---------- modo "biblioteca" (lista) ----------
function TelaSpotify:montarLista(W, H)
    local nivel = self.pilha[#self.pilha]
    local topo = self:cabecalho(W, nivel.titulo, nil)
    local margem = Screen:scaleBySize(20)
    local larg = W - 2 * margem
    local altura_linha = Screen:scaleBySize(64)
    local espaco = Screen:scaleBySize(4)
    local rodape_h = Screen:scaleBySize(40)
    local livre = H - topo:getSize().h - rodape_h
    local linhas = math.max(3, math.floor(livre / (altura_linha + espaco)))

    local itens, sel = nivel.itens, nivel.sel
    local pagina = math.floor((sel - 1) / linhas)
    local inicio = pagina * linhas + 1
    local g = VerticalGroup:new{ align = "left" }
    if #itens == 0 then
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(20) })
        table.insert(g, caixaTexto(nivel.vazio or "Nothing here.", 18, ESCURO, larg))
    end
    for i = inicio, math.min(#itens, inicio + linhas - 1) do
        local it = itens[i]
        local destaque = (i == sel)
        local fundo = destaque and PRETO or BRANCO
        local cor = destaque and BRANCO or PRETO
        local largura_txt = larg - Screen:scaleBySize(40)
        local linha = VerticalGroup:new{ align = "left",
            caixaTexto(it.texto, 19, cor, largura_txt, destaque, "left", fundo, 1),
        }
        if it.detalhe and it.detalhe ~= "" then
            table.insert(linha, caixaTexto(it.detalhe, 14, destaque and LINHA_COR or ESCURO, largura_txt, false, "left", fundo, 1))
        end
        local f = FrameContainer:new{
            width = larg, height = altura_linha, bordersize = destaque and 0 or Screen:scaleBySize(1),
            color = LINHA_COR, background = fundo,
            radius = Screen:scaleBySize(10), padding = Screen:scaleBySize(8),
            padding_left = Screen:scaleBySize(18), linha,
        }
        local indice = i
        table.insert(self.alvos, { w = f, acao = function() nivel.sel = indice; self:abrirItem() end })
        table.insert(g, f)
        table.insert(g, VerticalSpan:new{ width = espaco })
    end
    local paginas = math.max(1, math.ceil(#itens / linhas))
    local rodape = CenterContainer:new{ dimen = Geom:new{ w = larg, h = rodape_h },
        texto(paginas > 1 and string.format("page %d of %d", pagina + 1, paginas) or " ", 13, ESCURO) }
    return VerticalGroup:new{ align = "left",
        topo,
        FrameContainer:new{ bordersize = 0, padding = 0, padding_left = margem, background = BRANCO,
            VerticalGroup:new{ align = "left",
                FrameContainer:new{ bordersize = 0, padding = 0, height = livre, background = BRANCO, g },
                rodape,
            },
        },
    }
end

function TelaSpotify:montar()
    local W, H = self.dimen.w, self.dimen.h
    self.alvos = {}
    local conteudo
    if self.modo == "lista" and #self.pilha > 0 then
        conteudo = self:montarLista(W, H)
    else
        self.modo = "tocando"
        conteudo = self:montarTocando(W, H)
    end
    self[1] = FrameContainer:new{
        width = W, height = H, bordersize = 0, padding = 0, margin = 0, background = BRANCO,
        conteudo,
    }
end

function TelaSpotify:redesenhar(completo)
    self:montar()
    UIManager:setDirty(self, function() return completo and "full" or "ui", self.dimen end)
end

-- assinatura do que esta na tela: so redesenha se mudar
local function assinatura(st)
    if not st then return "erro" end
    if not st.ativo then return "parado" end
    return table.concat({ st.musica or "", st.artista or "", st.aparelho or "", tostring(st.tocando) }, "|")
end

function TelaSpotify:agendar()
    UIManager:unschedule(self._tic)
    self._tic = self._tic or function()
        if self._fechada then return end
        if self.modo == "tocando" then
            local st = self.plugin:estado()
            if assinatura(st) ~= assinatura(self.st) then self:redesenhar(false) end
        end
        self:agendar()
    end
    UIManager:scheduleIn(VERIFICAR_S, self._tic)
end

function TelaSpotify:executar(qual, arg)
    UIManager:nextTick(function()
        local r = self.plugin:acao(qual, arg)
        if r == "escolher" then
            self:escolherAparelho({ qual = qual, arg = arg }) -- toca la mesmo, sem apertar de novo
            return
        end
        UIManager:scheduleIn(0.8, function() -- da tempo do Spotify atualizar
            if not self._fechada then self.modo = "tocando"; self:redesenhar(false); self:agendar() end
        end)
    end)
end

-- ---------- navegacao da biblioteca ----------
function TelaSpotify:empilhar(titulo, itens, vazio)
    table.insert(self.pilha, { titulo = titulo, itens = itens, sel = 1, vazio = vazio })
    self.modo = "lista"
    self:redesenhar(false)
end

function TelaSpotify:voltar()
    table.remove(self.pilha)
    if #self.pilha == 0 then self.modo = "tocando" end
    self:redesenhar(false)
end

function TelaSpotify:mover(delta)
    local nivel = self.pilha[#self.pilha]
    if not nivel or #nivel.itens == 0 then return end
    nivel.sel = math.max(1, math.min(#nivel.itens, nivel.sel + delta))
    self:redesenhar(false)
end

function TelaSpotify:abrirItem()
    local nivel = self.pilha[#self.pilha]
    local it = nivel and nivel.itens[nivel.sel]
    if it and it.acao then it.acao() end
end

function TelaSpotify:tocar(uri)
    self.pilha = {}
    self:executar("tocar_contexto", uri)
end

function TelaSpotify:carregando(titulo)
    -- modal padrao do Lev (2-abrindo-lev.lua); fecha quando a lista for montada
    local M = rawget(_G, "__LEV_MODAL")
    if M then
        local m = M.mostrar("Loading…")
        UIManager:scheduleIn(0.5, function() M.fechar(m) end)
        return
    end
    self.pilha[#self.pilha + 1] = { titulo = titulo, itens = {}, sel = 1, vazio = "Loading…" }
    self.modo = "lista"
    self:redesenhar(false)
    UIManager:forceRePaint()
    table.remove(self.pilha)
end

function TelaSpotify:abrirBiblioteca()
    self.pilha = {}
    self:empilhar("Library", {
        { texto = "Liked Songs", detalhe = "play all", acao = function()
            local uid = self.plugin:usuario()
            if uid then self:tocar("spotify:user:" .. uid .. ":collection")
            else UIManager:show(InfoMessage:new{ text = "Couldn't identify your account.", timeout = 3 }) end
        end },
        { texto = "Playlists", detalhe = "yours and the ones you follow", acao = function() self:abrirPlaylists() end },
        { texto = "Albums", detalhe = "saved albums", acao = function() self:abrirAlbuns() end },
    })
end

function TelaSpotify:abrirPlaylists()
    self:carregando("Playlists")
    local lista, erro = self.plugin:listar("/me/playlists", 150)
    local itens = {}
    for _, p in ipairs(lista or {}) do
        if type(p) == "table" and p.uri then
            local uri = p.uri
            local n = type(p.tracks) == "table" and p.tracks.total
            local dono = type(p.owner) == "table" and p.owner.display_name or ""
            table.insert(itens, { texto = p.name or "—",
                detalhe = dono .. (n and string.format("  ·  %d songs", n) or ""),
                acao = function() self:tocar(uri) end })
        end
    end
    self:empilhar("Playlists", itens, lista and "No playlists." or ("Couldn't load: " .. tostring(erro)))
end

function TelaSpotify:abrirAlbuns()
    self:carregando("Albums")
    local lista, erro = self.plugin:listar("/me/albums", 150)
    local itens = {}
    for _, a in ipairs(lista or {}) do
        local alb = type(a) == "table" and a.album
        if type(alb) == "table" and alb.uri then
            local artistas = {}
            for _, ar in ipairs(alb.artists or {}) do table.insert(artistas, ar.name) end
            local uri = alb.uri
            table.insert(itens, { texto = alb.name or "—", detalhe = table.concat(artistas, ", "),
                acao = function() self:tocar(uri) end })
        end
    end
    self:empilhar("Albums", itens, lista and "No saved albums." or ("Couldn't load: " .. tostring(erro)))
end

-- pendente: o pedido que esperava um aparelho ({qual, arg}); ao escolher, ja executa
function TelaSpotify:escolherAparelho(pendente)
    local lista = self.plugin:aparelhos()
    if not lista then
        UIManager:show(InfoMessage:new{ text = "Couldn't list devices.", timeout = 4 })
        return
    end
    local ultimo = self.plugin.settings:readSetting("ultimo_aparelho")
    local itens = {}
    for _, d in ipairs(lista) do
        local id = d.id
        local detalhe = d.is_active and "playing now" or (id == ultimo and "last used") or d.type
        table.insert(itens, { texto = d.name, detalhe = detalhe, acao = function()
            self.pilha = {}
            self.modo = "tocando"
            UIManager:nextTick(function()
                if pendente then
                    self.plugin:acaoEm(id, pendente.qual, pendente.arg)
                else
                    self.plugin:acao("transferir", id)
                end
                UIManager:scheduleIn(0.8, function()
                    if not self._fechada then self:redesenhar(false); self:agendar() end
                end)
            end)
        end })
    end
    self.pilha = {}
    self:empilhar(pendente and "Where to play?" or "Play on…", itens,
        "No devices. Open Spotify on your phone or Mac, or ask Alexa.")
end

-- toque: na barra do ZenOS -> fecha e repassa o toque; senao aciona o item tocado
function TelaSpotify:onTapTela(_, ges)
    if self.altura_barra > 0 and ges.pos.y >= self.dimen.h then
        self:onFechar()
        UIManager:nextTick(function() UIManager:sendEvent(Event:new("Gesture", ges)) end)
        return true
    end
    for _, a in ipairs(self.alvos or {}) do
        if a.w.dimen and ges.pos:intersectWith(a.w.dimen) then
            a.acao()
            return true
        end
    end
    return true
end

-- botoes fisicos (via patch 2-botoes-lev.lua)
function TelaSpotify:levLateral(lado)
    if self.modo == "lista" then
        if lado == "direita" then self:mover(1)
        elseif lado == "esquerda" then self:mover(-1)
        elseif lado == "direita_longo" then self:abrirItem()
        elseif lado == "esquerda_longo" then self:voltar()
        end
        return
    end
    if lado == "direita" then self:executar("proxima")
    elseif lado == "esquerda" then self:executar("anterior")
    elseif lado == "direita_longo" then self:executar("tocar_pausar")
    elseif lado == "esquerda_longo" then self:onFechar()
    end
end

function TelaSpotify:onFechar()
    if self._fechada then return true end
    self._fechada = true
    UIManager:unschedule(self._tic)
    UIManager:close(self, "ui", self.dimen)
    return true
end

function TelaSpotify:onCloseWidget()
    self._fechada = true
    UIManager:unschedule(self._tic)
end

function Spotify:abrirPainel()
    if self.tela and not self.tela._fechada then
        self.tela.modo = "tocando"; self.tela.pilha = {}
        self.tela:redesenhar(false)
        return
    end
    local function abrir()
        self.tela = TelaSpotify:new{ plugin = self }
        UIManager:show(self.tela, "ui", self.tela.dimen)
        self.tela:agendar()
    end
    -- consultar o Spotify demora: mostra o modal padrao enquanto isso
    local M = rawget(_G, "__LEV_MODAL")
    if M and M.durante then M.durante("Loading…", abrir) else abrir() end
end

return Spotify
