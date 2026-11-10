-- Lev Neo (2026-11-09): Word of the day — uma palavra em ingles por dia para estudar.
-- * Lista propria de palavras (classe, definicao em ingles e exemplo), escolhida pelo dia do ano.
-- * Com Wi-Fi, busca pronuncia, mais definicoes, exemplos e sinonimos no Free Dictionary API
--   (api.dictionaryapi.dev) e guarda em settings/lev_palavras.lua (funciona offline depois).
-- * Tela de estudo (mesmo estilo da tela do Spotify, acima da barra inferior):
--   palavra, pronuncia, definicoes, exemplos, sinonimos; "Previous words" e "Quiz".
-- * Cartao no Inicio: faixa "Agora" (2-agora-lev.lua) usa _G.__LEV_PALAVRA.
-- Botoes fisicos na tela: laterais = palavra anterior / seguinte; esquerda segurada = sair.
-- Para desfazer: apague este arquivo.
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local Screen = Device.screen

local PRETO, BRANCO = Blitbuffer.COLOR_BLACK, Blitbuffer.COLOR_WHITE
local CINZA, CLARO = Blitbuffer.COLOR_DARK_GRAY, Blitbuffer.COLOR_LIGHT_GRAY

-- { palavra, classe, definicao, exemplo }
local PALAVRAS = {
    { "meticulous", "adjective", "Showing great attention to every small detail.", "She kept meticulous notes of every experiment." },
    { "resilient", "adjective", "Able to recover quickly after something difficult.", "Children are often more resilient than adults expect." },
    { "ubiquitous", "adjective", "Found everywhere; very common.", "Smartphones have become ubiquitous in modern life." },
    { "candid", "adjective", "Honest and direct, even when the truth is uncomfortable.", "He gave a candid answer about his mistakes." },
    { "eloquent", "adjective", "Able to express ideas clearly and persuasively.", "Her eloquent speech moved the whole audience." },
    { "pragmatic", "adjective", "Dealing with things in a practical, realistic way.", "We need a pragmatic solution, not a perfect one." },
    { "diligent", "adjective", "Working carefully and with steady effort.", "A diligent student reviews the lesson every night." },
    { "ambiguous", "adjective", "Open to more than one interpretation.", "The contract's wording was ambiguous." },
    { "tenacious", "adjective", "Holding firmly to a goal; not giving up easily.", "The tenacious reporter followed the story for years." },
    { "serene", "adjective", "Calm, peaceful and untroubled.", "The lake looked serene in the early morning." },
    { "frugal", "adjective", "Careful not to waste money or resources.", "They lived a frugal life and saved for travel." },
    { "vivid", "adjective", "Producing strong, clear images in the mind.", "He has vivid memories of his first trip abroad." },
    { "profound", "adjective", "Very deep, intense or far-reaching.", "The book had a profound effect on my thinking." },
    { "subtle", "adjective", "Delicate and hard to notice at first.", "There is a subtle difference between the two colors." },
    { "inevitable", "adjective", "Certain to happen; impossible to avoid.", "Some change is inevitable as a company grows." },
    { "genuine", "adjective", "Real and sincere, not fake.", "She showed genuine interest in our ideas." },
    { "thorough", "adjective", "Complete and careful, covering every part.", "The doctor did a thorough examination." },
    { "reluctant", "adjective", "Unwilling and hesitant to do something.", "He was reluctant to leave the party early." },
    { "obsolete", "adjective", "No longer used because something newer exists.", "Fax machines are almost obsolete now." },
    { "versatile", "adjective", "Able to adapt to many different uses or tasks.", "A versatile actor can play comedy and drama." },
    { "concise", "adjective", "Giving a lot of information in few words.", "Keep your summary short and concise." },
    { "arduous", "adjective", "Very difficult and tiring.", "The climb to the summit was long and arduous." },
    { "benevolent", "adjective", "Kind and wanting to help others.", "A benevolent stranger paid for our coffee." },
    { "cautious", "adjective", "Careful to avoid risks or danger.", "Be cautious when driving on wet roads." },
    { "elusive", "adjective", "Difficult to find, catch or understand.", "Happiness can feel elusive when you chase it." },
    { "feasible", "adjective", "Possible to do or achieve.", "Is it feasible to finish the project by Friday?" },
    { "gregarious", "adjective", "Enjoying the company of other people.", "Our gregarious neighbor knows everyone on the street." },
    { "humble", "adjective", "Not proud; modest about your own importance.", "Despite his success, he remained humble." },
    { "impeccable", "adjective", "Perfect; without any fault.", "Her English pronunciation is impeccable." },
    { "lucid", "adjective", "Clear and easy to understand.", "The teacher gave a lucid explanation of the rule." },
    { "mundane", "adjective", "Ordinary and not interesting.", "He wanted to escape his mundane routine." },
    { "nostalgic", "adjective", "Feeling a happy sadness for the past.", "Old songs make me feel nostalgic." },
    { "outspoken", "adjective", "Saying openly what you think.", "She is an outspoken critic of the plan." },
    { "plausible", "adjective", "Seeming reasonable or likely to be true.", "His excuse sounded plausible at first." },
    { "relentless", "adjective", "Continuing strongly without stopping.", "The relentless rain lasted all week." },
    { "spontaneous", "adjective", "Done naturally, without planning.", "We took a spontaneous trip to the beach." },
    { "trivial", "adjective", "Of little value or importance.", "Don't argue about trivial details." },
    { "vulnerable", "adjective", "Easily hurt, physically or emotionally.", "Elderly people are more vulnerable to the flu." },
    { "wary", "adjective", "Careful because you think something may be wrong.", "Be wary of offers that look too good." },
    { "zealous", "adjective", "Full of strong enthusiasm for a cause.", "The zealous fans waited outside for hours." },
    { "acknowledge", "verb", "To accept or admit that something is true.", "He acknowledged that he had made an error." },
    { "advocate", "verb", "To publicly support an idea or cause.", "She advocates for better public libraries." },
    { "alleviate", "verb", "To make pain or a problem less severe.", "This medicine will alleviate the headache." },
    { "anticipate", "verb", "To expect something and prepare for it.", "We anticipate a lot of traffic tomorrow." },
    { "clarify", "verb", "To make something easier to understand.", "Could you clarify what you mean?" },
    { "cultivate", "verb", "To develop a skill, habit or relationship over time.", "Reading daily helps you cultivate focus." },
    { "deteriorate", "verb", "To become worse over time.", "The old bridge began to deteriorate." },
    { "embrace", "verb", "To accept something willingly and with enthusiasm.", "The team embraced the new method." },
    { "endure", "verb", "To suffer something difficult patiently.", "They had to endure a cold winter." },
    { "enhance", "verb", "To improve the quality or value of something.", "Good lighting can enhance a photograph." },
    { "foster", "verb", "To encourage the development of something.", "Teachers should foster curiosity." },
    { "hinder", "verb", "To make something slower or more difficult.", "Bad weather hindered the rescue." },
    { "linger", "verb", "To stay somewhere longer than necessary.", "The smell of coffee lingered in the room." },
    { "mitigate", "verb", "To make something bad less serious.", "Trees can mitigate the effects of heat." },
    { "overcome", "verb", "To succeed in dealing with a difficulty.", "She overcame her fear of public speaking." },
    { "persevere", "verb", "To keep trying despite difficulties.", "If you persevere, your English will improve." },
    { "ponder", "verb", "To think carefully about something.", "He pondered the question before answering." },
    { "relish", "verb", "To enjoy something very much.", "I relish quiet Sunday mornings." },
    { "scrutinize", "verb", "To examine something very carefully.", "The editor scrutinized every sentence." },
    { "thrive", "verb", "To grow, develop or succeed well.", "Plants thrive in this warm climate." },
    { "undermine", "verb", "To gradually weaken something.", "Constant criticism can undermine confidence." },
    { "yearn", "verb", "To want something very strongly.", "She yearned to see her family again." },
    { "convey", "verb", "To communicate an idea or feeling.", "Music can convey emotions words cannot." },
    { "dwell", "verb", "To keep thinking or talking about something.", "Don't dwell on your past mistakes." },
    { "grasp", "verb", "To understand something completely.", "It took me a while to grasp the idea." },
    { "procrastinate", "verb", "To delay doing something you should do.", "I tend to procrastinate when a task feels big." },
    { "reconcile", "verb", "To restore a friendly relationship; to make things agree.", "The brothers finally reconciled." },
    { "savor", "verb", "To enjoy something slowly and completely.", "Savor every page of a good book." },
    { "wander", "verb", "To walk around without a fixed direction.", "We wandered through the old streets." },
    { "insight", "noun", "A deep and clear understanding of something.", "The interview gave us insight into her work." },
    { "dilemma", "noun", "A situation where you must choose between two difficult options.", "Taking the job created a real dilemma." },
    { "endeavor", "noun", "A serious attempt to do something.", "Learning a language is a long endeavor." },
    { "hindsight", "noun", "Understanding an event only after it has happened.", "In hindsight, we should have left earlier." },
    { "milestone", "noun", "An important event or stage in progress.", "Finishing the first book was a milestone." },
    { "nuance", "noun", "A very small difference in meaning or feeling.", "Translation often loses the nuance of a joke." },
    { "perspective", "noun", "A particular way of seeing things.", "Travel gives you a new perspective." },
    { "resilience", "noun", "The ability to recover quickly from difficulties.", "Her resilience inspired everyone." },
    { "solitude", "noun", "The state of being alone, often peacefully.", "He enjoys the solitude of early mornings." },
    { "wisdom", "noun", "The ability to make good judgments from experience.", "Grandparents often share great wisdom." },
    { "awe", "noun", "A feeling of great respect mixed with wonder.", "We watched the sunset in awe." },
    { "clarity", "noun", "The quality of being clear and easy to understand.", "Writing improves the clarity of your thoughts." },
    { "curiosity", "noun", "A strong desire to know or learn something.", "Curiosity is the engine of learning." },
    { "empathy", "noun", "The ability to understand and share another's feelings.", "Good leaders show empathy." },
    { "gratitude", "noun", "The feeling of being thankful.", "She expressed her gratitude with a letter." },
    { "integrity", "noun", "The quality of being honest and having strong principles.", "He is a man of great integrity." },
    { "momentum", "noun", "The force that keeps something moving or growing.", "The campaign gained momentum after the debate." },
    { "paradox", "noun", "A statement that seems to contradict itself but may be true.", "It's a paradox: the more I learn, the less I know." },
    { "routine", "noun", "A usual, regular way of doing things.", "Reading before bed is part of my routine." },
    { "threshold", "noun", "The point at which something begins or changes.", "We are on the threshold of a new era." },
    { "turmoil", "noun", "A state of great confusion or disorder.", "The country was in political turmoil." },
    { "whim", "noun", "A sudden wish or idea, often without reason.", "She bought the dress on a whim." },
    { "meanwhile", "adverb", "At the same time; while something else happens.", "Dinner is cooking; meanwhile, set the table." },
    { "nevertheless", "adverb", "In spite of what was just said.", "It was raining; nevertheless, we went out." },
    { "seldom", "adverb", "Not often; rarely.", "He seldom watches television." },
    { "thoroughly", "adverb", "Completely and carefully.", "Read the instructions thoroughly." },
    { "eventually", "adverb", "In the end, after a long time.", "Eventually, the rain stopped." },
    { "deliberately", "adverb", "On purpose; intentionally.", "He deliberately left the door open." },
    { "barely", "adverb", "Only just; almost not.", "I could barely hear the music." },
    { "albeit", "conjunction", "Although; even though.", "It was a good result, albeit a small one." },
    { "whereas", "conjunction", "In contrast with the fact that.", "I like tea, whereas my wife prefers coffee." },
}

local ARQ = DataStorage:getSettingsDir() .. "/lev_palavras.lua"
local dados -- cache e progresso

local function abrirDados()
    if not dados then dados = LuaSettings:open(ARQ) end
    return dados
end

local function indiceDoDia(desloc)
    local t = os.time() + (desloc or 0) * 86400
    local d = os.date("*t", t)
    local seq = d.year * 366 + d.yday
    return (seq % #PALAVRAS) + 1, t
end

local function entrada(i)
    local p = PALAVRAS[i]
    local e = { palavra = p[1], classe = p[2], definicao = p[3], exemplo = p[4] }
    local cache = abrirDados():readSetting("dic") or {}
    local c = cache[p[1]]
    if type(c) == "table" then
        e.fonetica, e.extras, e.sinonimos = c.fonetica, c.extras, c.sinonimos
    end
    return e
end

-- busca no Free Dictionary API (com Wi-Fi) e guarda no cache
local function buscarDicionario(palavra)
    local cache = abrirDados():readSetting("dic") or {}
    if cache[palavra] then return true end
    local ok_http, http = pcall(require, "socket.http")
    local ok_ltn, ltn12 = pcall(require, "ltn12")
    local ok_su, socketutil = pcall(require, "socketutil")
    if not (ok_http and ok_ltn) then return false end
    local partes = {}
    if ok_su then socketutil:set_timeout(6, 10) end
    local ok, _, codigo = pcall(http.request, {
        url = "https://api.dictionaryapi.dev/api/v2/entries/en/" .. palavra,
        sink = ltn12.sink.table(partes),
        headers = { ["User-Agent"] = "KOReader-Lev" },
    })
    if ok_su then socketutil:reset_timeout() end
    if not ok or codigo ~= 200 then return false end
    local ok_j, j = pcall(require("json").decode, table.concat(partes))
    if not ok_j or type(j) ~= "table" or type(j[1]) ~= "table" then return false end
    local r = { extras = {}, sinonimos = {} }
    local vistos = {}
    for _, ent in ipairs(j) do
        r.fonetica = r.fonetica or ent.phonetic
        for _, ph in ipairs(ent.phonetics or {}) do r.fonetica = r.fonetica or ph.text end
        for _, m in ipairs(ent.meanings or {}) do
            for _, d in ipairs(m.definitions or {}) do
                if #r.extras < 4 and d.definition then
                    table.insert(r.extras, { classe = m.partOfSpeech, definicao = d.definition, exemplo = d.example })
                end
                for _, s in ipairs(d.synonyms or {}) do
                    if not vistos[s] and #r.sinonimos < 8 then vistos[s] = true; table.insert(r.sinonimos, s) end
                end
            end
            for _, s in ipairs(m.synonyms or {}) do
                if not vistos[s] and #r.sinonimos < 8 then vistos[s] = true; table.insert(r.sinonimos, s) end
            end
        end
    end
    cache[palavra] = r
    abrirDados():saveSetting("dic", cache)
    abrirDados():flush()
    return true
end

-- ---------- tela de estudo ----------
local function face(tam, titulo)
    if titulo then
        local ok, f = pcall(Font.getFace, Font, "literata/Literata-Bold.ttf", tam)
        if ok and f then return f end
    end
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, f = pcall(lf.getFace, tam)
        if ok2 and f then return f end
    end
    return Font:getFace("cfont", tam)
end

local function caixa(t, tam, cor, largura, opts)
    opts = opts or {}
    return TextBoxWidget:new{ text = t or "", face = opts.face or face(tam), fgcolor = cor or PRETO,
        width = largura, alignment = opts.alinhamento or "left", bold = opts.negrito }
end

local TelaPalavra = InputContainer:extend{
    covers_fullscreen = false,
    _lev_spotify = true, -- reconhecida pelo patch de botoes (laterais chamam levLateral)
}

function TelaPalavra:init()
    local W, H = Screen:getWidth(), Screen:getHeight()
    local barra = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
    if barra < 0 or barra > H / 3 then barra = 0 end
    self.altura_barra = barra
    self.dimen = Geom:new{ x = 0, y = 0, w = W, h = H - barra }
    self.ges_events.TapTela = { GestureRange:new{ ges = "tap", range = Geom:new{ x = 0, y = 0, w = W, h = H } } }
    self.desloc = self.desloc or 0
    self.modo = "palavra"
    self:montar()
end

function TelaPalavra:botao(rotulo, acao)
    local f = FrameContainer:new{
        bordersize = Screen:scaleBySize(1), color = PRETO, background = BRANCO,
        radius = Screen:scaleBySize(18), padding = Screen:scaleBySize(9),
        padding_left = Screen:scaleBySize(18), padding_right = Screen:scaleBySize(18),
        TextWidget:new{ text = rotulo, face = face(16) },
    }
    table.insert(self.alvos, { w = f, acao = acao })
    return f
end

function TelaPalavra:montarPalavra(W)
    local i, t = indiceDoDia(self.desloc)
    local e = entrada(i)
    local m = Screen:scaleBySize(28)
    local larg = W - 2 * m
    local g = VerticalGroup:new{ align = "left" }
    local quando = self.desloc == 0 and "Word of the day" or os.date("Word of %b %d", t)
    table.insert(g, TextWidget:new{ text = quando, face = face(15), fgcolor = CINZA })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(g, caixa(e.palavra, 40, PRETO, larg, { face = face(40, true) }))
    local linha = e.classe .. (e.fonetica and ("   " .. e.fonetica) or "")
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
    table.insert(g, caixa(linha, 17, CINZA, larg))
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(18) })
    table.insert(g, caixa(e.definicao, 21, PRETO, larg))
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(8) })
    table.insert(g, caixa("“" .. e.exemplo .. "”", 18, CINZA, larg, { face = face(18) }))
    -- definicoes extras do dicionario (quando ja baixadas)
    for n, x in ipairs(e.extras or {}) do
        if n > 2 then break end
        if x.definicao and x.definicao ~= e.definicao then
            table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(14) })
            table.insert(g, caixa((x.classe and (x.classe .. " · ") or "") .. x.definicao, 16, PRETO, larg))
            if x.exemplo then
                table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
                table.insert(g, caixa("“" .. x.exemplo .. "”", 15, CINZA, larg))
            end
        end
    end
    if e.sinonimos and #e.sinonimos > 0 then
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(14) })
        table.insert(g, caixa("Synonyms: " .. table.concat(e.sinonimos, ", "), 15, CINZA, larg))
    end
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(24) })
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:botao("‹ Previous", function() self:ir(-1) end),
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        self:botao("Quiz", function() self:abrirQuiz() end),
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        self:botao(self.desloc < 0 and "Next ›" or "Today", function()
            if self.desloc < 0 then self:ir(1) else self.desloc = 0; self:redesenhar() end
        end),
    })
    return FrameContainer:new{ bordersize = 0, padding = m, padding_top = Screen:scaleBySize(30), background = BRANCO, g }
end

-- quiz: qual e o significado? (4 opcoes, palavras recentes)
function TelaPalavra:abrirQuiz()
    local i = indiceDoDia(self.desloc)
    local certo = PALAVRAS[i]
    local opcoes = { certo }
    local usados = { [i] = true }
    local semente = os.time()
    while #opcoes < 4 do
        semente = (semente * 1103515245 + 12345) % 2147483648
        local j = (semente % #PALAVRAS) + 1
        if not usados[j] then usados[j] = true; table.insert(opcoes, PALAVRAS[j]) end
    end
    for k = #opcoes, 2, -1 do -- embaralha
        semente = (semente * 1103515245 + 12345) % 2147483648
        local r = (semente % k) + 1
        opcoes[k], opcoes[r] = opcoes[r], opcoes[k]
    end
    self.quiz = { certo = certo, opcoes = opcoes, resposta = nil }
    self.modo = "quiz"
    self:redesenhar()
end

function TelaPalavra:montarQuiz(W)
    local q = self.quiz
    local m = Screen:scaleBySize(28)
    local larg = W - 2 * m
    local g = VerticalGroup:new{ align = "left" }
    table.insert(g, TextWidget:new{ text = "Quiz · what does it mean?", face = face(15), fgcolor = CINZA })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(g, caixa(q.certo[1], 36, PRETO, larg, { face = face(36, true) }))
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(18) })
    for _, op in ipairs(q.opcoes) do
        local marcado = q.resposta ~= nil
        local e_certo = op == q.certo
        local escolhido = q.resposta == op
        local fundo = (marcado and e_certo) and PRETO or BRANCO
        local cor = (marcado and e_certo) and BRANCO or PRETO
        local prefixo = marcado and (e_certo and "✓  " or (escolhido and "✗  " or "")) or ""
        local f = FrameContainer:new{
            bordersize = Screen:scaleBySize(1), color = escolhido and PRETO or CLARO, background = fundo,
            radius = Screen:scaleBySize(10), padding = Screen:scaleBySize(12), width = larg,
            caixa(prefixo .. op[3], 17, cor, larg - Screen:scaleBySize(26), { }),
        }
        f[1].bgcolor = fundo
        table.insert(self.alvos, { w = f, acao = function()
            if not q.resposta then
                q.resposta = op
                local acertos = abrirDados():readSetting("acertos") or 0
                local tentativas = abrirDados():readSetting("tentativas") or 0
                abrirDados():saveSetting("tentativas", tentativas + 1)
                if op == q.certo then abrirDados():saveSetting("acertos", acertos + 1) end
                abrirDados():flush()
                self:redesenhar()
            end
        end })
        table.insert(g, f)
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(8) })
    end
    local acertos = abrirDados():readSetting("acertos") or 0
    local tentativas = abrirDados():readSetting("tentativas") or 0
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(g, TextWidget:new{ text = string.format("Score: %d of %d", acertos, tentativas), face = face(14), fgcolor = CINZA })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(16) })
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:botao("‹ Back to word", function() self.modo = "palavra"; self:redesenhar() end),
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        self:botao("Another", function() self:abrirQuizAleatorio() end),
    })
    return FrameContainer:new{ bordersize = 0, padding = m, padding_top = Screen:scaleBySize(30), background = BRANCO, g }
end

function TelaPalavra:abrirQuizAleatorio()
    self.desloc = -((os.time() % 20) + 1) -- uma das ultimas ~20 palavras
    self:abrirQuiz()
end

function TelaPalavra:montar()
    local W, H = self.dimen.w, self.dimen.h
    self.alvos = {}
    local conteudo = self.modo == "quiz" and self:montarQuiz(W) or self:montarPalavra(W)
    self[1] = FrameContainer:new{ width = W, height = H, bordersize = 0, padding = 0, margin = 0, background = BRANCO, conteudo }
end

function TelaPalavra:redesenhar()
    self:montar()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

function TelaPalavra:ir(delta)
    self.desloc = math.min(0, self.desloc + delta)
    self.modo = "palavra"
    local i = indiceDoDia(self.desloc)
    local M = rawget(_G, "__LEV_MODAL")
    local palavra = PALAVRAS[i][1]
    local cache = abrirDados():readSetting("dic") or {}
    if M and not cache[palavra] then
        M.durante("Loading…", function() pcall(buscarDicionario, palavra); self:redesenhar() end)
    else
        self:redesenhar()
    end
end

function TelaPalavra:onTapTela(_, ges)
    if self.altura_barra > 0 and ges.pos.y >= self.dimen.h then
        self:onFechar()
        UIManager:nextTick(function() UIManager:sendEvent(Event:new("Gesture", ges)) end)
        return true
    end
    for _, a in ipairs(self.alvos or {}) do
        if a.w.dimen and ges.pos:intersectWith(a.w.dimen) then a.acao(); return true end
    end
    return true
end

function TelaPalavra:levLateral(lado)
    if lado == "direita" then self:ir(1)
    elseif lado == "esquerda" then self:ir(-1)
    elseif lado == "direita_longo" then self:abrirQuiz()
    elseif lado == "esquerda_longo" then self:onFechar()
    end
end

function TelaPalavra:onFechar()
    if self._fechada then return true end
    self._fechada = true
    UIManager:close(self, "ui", self.dimen)
    return true
end
function TelaPalavra:onCloseWidget() self._fechada = true end

-- ---------- API para o cartao do Inicio ----------
local P = {}
function P.hoje()
    return entrada((indiceDoDia(0)))
end
function P.abrir()
    local M = rawget(_G, "__LEV_MODAL")
    local function mostrar()
        pcall(buscarDicionario, P.hoje().palavra) -- pronuncia e extras (se houver Wi-Fi)
        local tela = TelaPalavra:new{}
        UIManager:show(tela, "ui", tela.dimen)
    end
    if M and M.durante then M.durante("Loading…", mostrar) else mostrar() end
end
-- pre-busca silenciosa da palavra do dia (para abrir rapido e funcionar offline)
UIManager:scheduleIn(30, function() pcall(buscarDicionario, P.hoje().palavra) end)
_G.__LEV_PALAVRA = P

logger.info("Lev: Word of the day ativo,", #PALAVRAS, "palavras")
