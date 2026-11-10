-- Lev Neo (2026-11-06; v4 2026-11-10: significado da palavra no cartao): faixa "Agora" no Inicio do ZenOS.
-- Dois cartoes compactos lado a lado, no estilo claro do Inicio (v3: the news -> Word of the day):
--   Spotify  : o que esta tocando (musica e artista); toque abre a tela do Spotify
--   Word of the day : palavra do dia em ingles e definicao; toque abre a tela de estudo
-- Usa o registro oficial de faixas do Inicio do ZenOS (home/components/registry).
-- O Spotify e consultado no maximo 1x por minuto, so quando o Inicio e montado,
-- e a faixa so e redesenhada se a musica mudar.
-- Para desfazer: apague este arquivo e a linha "lev_agora" de rows em settings/ZenOS/config.lua.
local userpatch = require("userpatch")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Screen = Device.screen

local ID = "lev_agora"
local PASTA_NEWS = "/mnt/fat/the news"
local MESES = { "jan.", "fev.", "mar.", "abr.", "mai.", "jun.", "jul.", "ago.", "set.", "out.", "nov.", "dez." }
local CINZA = Blitbuffer.COLOR_DARK_GRAY
local BORDA = Blitbuffer.COLOR_LIGHT_GRAY

local function fonte(tamanho)
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, face = pcall(lf.getFace, tamanho)
        if ok2 and face then return face end
    end
    return Font:getFace("cfont", tamanho)
end

-- ---------- the news ----------
local function ultimaEdicao()
    if lfs.attributes(PASTA_NEWS, "mode") ~= "directory" then return nil end
    local melhor_chave, melhor_nome
    for nome in lfs.dir(PASTA_NEWS) do
        if nome:match("%.epub$") then
            local chave = nome:match("^(%d%d%-%d%d%-%d%d_%d%d%-%d%d)") or ""
            if not melhor_chave or chave > melhor_chave then melhor_chave, melhor_nome = chave, nome end
        end
    end
    return melhor_nome and (PASTA_NEWS .. "/" .. melhor_nome), melhor_nome
end

local function nomeEdicao(nome)
    local _aa, mm, dd, hh = (nome or ""):match("^(%d%d)%-(%d%d)%-(%d%d)_(%d%d)")
    if not dd then return "edição mais recente" end
    local periodo = tonumber(hh) >= 12 and "Noite" or "Manhã"
    return string.format("%s · %d de %s", periodo, tonumber(dd), MESES[tonumber(mm)] or mm)
end

local manchetes = {} -- cache por arquivo
local function limparHtml(t)
    t = t:gsub("<[^>]+>", ""):gsub("&nbsp;", " "):gsub("&amp;", "&"):gsub("&quot;", "\""):gsub("&#39;", "'")
    return (t:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function manchete(arq)
    if manchetes[arq] ~= nil then return manchetes[arq] or nil end
    local achou = false
    local ok = pcall(function()
        local Archiver = require("ffi/archiver")
        local r = Archiver.Reader:new()
        if not r:open(arq) then return end
        local paginas = {}
        for e in r:iterate() do
            if e.mode == "file" and e.path:match("%.x?html?$") then table.insert(paginas, e.path) end
        end
        for _, p in ipairs(paginas) do
            local html = r:extractToMemory(p)
            if html then
                for attrs, txt in html:gmatch("<h1([^>]*)>(.-)</h1>") do
                    if attrs:find("heading", 1, true) then
                        local t = limparHtml(txt)
                        -- manchete de verdade: pelo menos 3 letras (pula "....", "***", "Título")
                        local letras = select(2, t:gsub("%a", ""))
                        if letras >= 3 and #t > 3 and not t:lower():match("^t[íi]tulo$") then achou = t; break end
                    end
                end
            end
            if achou then break end
        end
        r:close()
    end)
    if not ok then achou = false end
    manchetes[arq] = achou
    return achou or nil
end

-- ---------- Spotify (cache, consulta no maximo 1x por minuto) ----------
local sp = { st = nil, t = 0, buscando = false }

local function pluginSpotify()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager.instance
    if fm and fm.spotify then return fm.spotify end
    local ok_pl, PluginLoader = pcall(require, "pluginloader")
    return ok_pl and PluginLoader.getPluginInstance and PluginLoader:getPluginInstance("spotify") or nil
end

local function assinatura(st)
    if not st then return "?" end
    if not st.ativo then return "parado" end
    return (st.musica or "") .. "|" .. (st.artista or "") .. "|" .. tostring(st.tocando)
end

local registrar -- definido abaixo

local function atualizarSpotify()
    if sp.buscando or os.time() - sp.t < 60 then return end
    sp.buscando = true
    UIManager:scheduleIn(1.5, function()
        local antes = assinatura(sp.st)
        local plugin = pluginSpotify()
        local ok, st = false, nil
        if plugin and plugin.estado then ok, st = pcall(plugin.estado, plugin) end
        sp.t = os.time()
        sp.buscando = false
        if ok and st then sp.st = st end
        if assinatura(sp.st) ~= antes and registrar then registrar() end -- redesenha so se mudou
    end)
end

-- ---------- cartao ----------
-- cartao compacto: [icone] rotulo · detalhe  /  titulo em negrito (1 linha)
local function cartao(largura, altura, icone, rotulo, titulo, detalhe, ao_tocar, texto)
    local pad_h = Screen:scaleBySize(12)
    local interno = largura - 2 * pad_h - 2
    local icone_px = Screen:scaleBySize(24)
    local cab_txt = rotulo .. ((detalhe and detalhe ~= "") and ("  ·  " .. detalhe) or "")
    local cab = HorizontalGroup:new{ align = "center",
        IconWidget:new{ icon = icone, width = icone_px, height = icone_px },
        HorizontalSpan:new{ width = Screen:scaleBySize(8) },
        TextWidget:new{ text = cab_txt, face = fonte(15), fgcolor = CINZA,
            max_width = interno - icone_px - Screen:scaleBySize(8) },
    }
    local corpo = VerticalGroup:new{ align = "left",
        cab,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        TextWidget:new{ text = titulo or "", face = fonte(20), bold = true, max_width = interno },
    }
    -- texto extra (ex.: o significado da palavra), no maximo 2 linhas, com "…" se passar
    if texto and texto ~= "" then
        local face = fonte(15)
        local linha = TextWidget:new{ text = "Ag", face = face }
        local lh = linha:getSize().h
        linha:free()
        table.insert(corpo, VerticalSpan:new{ width = Screen:scaleBySize(4) })
        table.insert(corpo, TextBoxWidget:new{ text = texto, face = face, width = interno,
            fgcolor = Blitbuffer.COLOR_BLACK, height = math.floor(lh * 2.3), height_adjust = true,
            height_overflow_show_ellipsis = true })
    end
    -- centraliza o conteudo na altura do cartao
    local pad_v = math.max(Screen:scaleBySize(6), math.floor((altura - 2 - corpo:getSize().h) / 2))
    local frame = FrameContainer:new{
        width = largura, height = altura, bordersize = Screen:scaleBySize(1), color = BORDA,
        radius = Screen:scaleBySize(12), padding = 0,
        padding_left = pad_h, padding_right = pad_h, padding_top = pad_v, padding_bottom = pad_v,
        background = Blitbuffer.COLOR_WHITE,
        corpo,
    }
    local toque = InputContainer:new{
        dimen = Geom:new{ w = largura, h = altura },
        ges_events = {
            TapAgora = { GestureRange:new{ ges = "tap", range = Geom:new{
                x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() } } },
        },
        frame,
    }
    toque.onTapAgora = function(self, _arg, ges)
        if not (self.dimen and ges and ges.pos and self.dimen:contains(ges.pos)) then return false end
        UIManager:nextTick(ao_tocar)
        return true
    end
    return toque
end

local function construir(ctx)
    local W, H = ctx.width, ctx.height
    local gap = Screen:scaleBySize(12)
    local lw = math.floor((W - gap) / 2)

    -- Spotify
    atualizarSpotify()
    local st = sp.st
    local sp_titulo, sp_sub, sp_rot
    if st and st.ativo then
        sp_rot = st.tocando and "Now playing" or "Paused"
        sp_titulo, sp_sub = st.musica or "—", st.artista or ""
    elseif st then
        sp_rot, sp_titulo, sp_sub = "Spotify", "Nothing playing", "tap to play"
    else
        sp_rot, sp_titulo, sp_sub = "Spotify", "Spotify", "tap to open"
    end
    local c_sp = cartao(lw, H, "spotify_lev", sp_rot, sp_titulo, sp_sub, function()
        local plugin = pluginSpotify()
        if plugin and plugin.abrirPainel then plugin:abrirPainel() end -- ja mostra "Loading…"
    end)

    -- Word of the day (2-palavra-lev.lua) no lugar do the news
    local P = rawget(_G, "__LEV_PALAVRA")
    local e = P and P.hoje()
    local c_tn = cartao(W - lw - gap, H, "tab_translate", "Word of the day",
        e and e.palavra or "Word of the day",
        e and e.classe or "tap to open", function()
            local PP = rawget(_G, "__LEV_PALAVRA")
            if PP then PP.abrir() end
        end, e and e.definicao)

    return HorizontalGroup:new{ align = "top", c_sp, HorizontalSpan:new{ width = gap }, c_tn }
end

userpatch.registerPatchPluginFunc("zenos", function()
    local ok, Registry = pcall(require, "modules/filebrowser/patches/home/components/registry")
    if not ok or not Registry or not Registry.register then
        logger.warn("Lev agora: registro do Inicio do ZenOS nao encontrado")
        return
    end
    registrar = function()
        Registry.register(ID, function(ctx)
            local ok_b, w = pcall(construir, ctx)
            if ok_b then return w end
            logger.warn("Lev agora: erro ao montar:", w)
        end, { label = "Agora", size = { units = 2 } })
    end
    registrar()
    logger.info("Lev: faixa Agora no Inicio ativa")
end)
