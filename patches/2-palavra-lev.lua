-- Lev Neo (2026-11-10, v2): Expression of the day — uma expressao util em ingles por dia,
-- para ganhar fluencia (antes: palavra do dia).
-- * Lista propria de ~130 expressoes de conversa real: conectores, opinioes, trabalho,
--   phrasal verbs, reacoes, pedidos educados, tempo e planos, idioms e erros classicos
--   de brasileiros. Cada uma tem significado em ingles simples, equivalente natural em
--   portugues, dois exemplos e uma dica de uso. Tudo offline.
-- * Tela de estudo acima da barra inferior: expressao, significado, "In Portuguese",
--   exemplos e dica; "Previous", "Quiz" e "Today".
-- * Quiz alterna dois tipos: "What does it mean?" e "How do you say it in English?".
-- * Cartao no Inicio: faixa "Agora" (2-agora-lev.lua) usa _G.__LEV_PALAVRA.
-- Botoes fisicos na tela: laterais = anterior / seguinte; direita segurada = quiz;
-- esquerda segurada = sair.
-- Para desfazer: apague este arquivo (versao anterior: 2-palavra-lev.lua.v1_palavras no Mac).
local Blitbuffer = require("ffi/blitbuffer")
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

-- { expressao, categoria, significado, em portugues, exemplo 1, exemplo 2, dica }
local EXPRESSOES = {
    -- Conversation
    { "By the way", "Conversation", "Used to add something new to the conversation.", "A propósito / aliás",
      "By the way, did you call your mom back?", "Oh, by the way, the meeting moved to 3 p.m.",
      "In texts people write BTW." },
    { "Speaking of which", "Conversation", "Used to connect a new idea to something just mentioned.", "Falando nisso",
      "You said you were hungry. Speaking of which, want to grab lunch?", "Speaking of which, have you finished that report?",
      "A smooth way to change topic without sounding abrupt." },
    { "Long story short", "Conversation", "Used to skip the details and give the main point.", "Resumindo a história",
      "Long story short, we missed the flight.", "Long story short, I got the job.",
      "Great for telling stories without getting lost in details." },
    { "What I mean is…", "Conversation", "Used to explain again what you just said, more clearly.", "O que eu quero dizer é…",
      "What I mean is, we need more time, not more people.", "Sorry, that came out wrong. What I mean is I liked it.",
      "Use it to fix a sentence that came out confusing. Fluent speakers do this all the time." },
    { "Let me see", "Conversation", "Used to give yourself a moment to think.", "Deixa eu ver",
      "Let me see… I think it was last Tuesday.", "How many people are coming? Let me see, about twelve.",
      "Sounds much more natural than a long \"ehhh\"." },
    { "Anyway", "Conversation", "Used to return to the main topic or to close a topic.", "Enfim / de qualquer forma",
      "Anyway, where was I?", "Anyway, I have to go. Talk soon!",
      "Natural way to end a conversation politely." },
    { "To be honest", "Conversation", "Used before saying what you really think.", "Para ser sincero",
      "To be honest, I didn't like the movie.", "To be honest, I forgot about it.",
      "In texts: TBH. \"Honestly\" works too." },
    { "As far as I know", "Conversation", "Based on the information I have (I might be wrong).", "Até onde eu sei",
      "As far as I know, the store opens at nine.", "As far as I know, nobody has complained.",
      "Protects you when you're not 100% sure." },
    { "If I remember correctly", "Conversation", "Used when you think something is true but aren't certain.", "Se não me engano",
      "If I remember correctly, she lives in Boston.", "The trip was in 2019, if I remember correctly.",
      "Can go at the start or at the end of the sentence." },
    { "It depends on…", "Conversation", "The answer changes according to something else.", "Depende de…",
      "It depends on the weather.", "Whether we go or not depends on the price.",
      "Classic mistake: it's \"depends ON\", never \"depends OF\"." },
    { "Kind of", "Conversation", "A little; not completely.", "Meio que / mais ou menos",
      "I'm kind of tired today.", "It was kind of funny, actually.",
      "\"Sort of\" means the same. Very common in casual speech." },
    { "I guess", "Conversation", "I think so, but I'm not very sure.", "Acho que sim / pelo jeito",
      "I guess you're right.", "— Are you coming? — I guess so.",
      "Softer and less certain than \"I think\"." },
    { "What's up?", "Conversation", "Informal hello: how are you, what's new?", "E aí? / Beleza?",
      "Hey, what's up? Long time no see!", "— What's up? — Not much, just working.",
      "Answer with \"Not much\" or \"Nothing much\", not \"I'm fine\"." },

    -- Opinions
    { "If you ask me", "Opinions", "Used to give your personal opinion, often a strong one.", "Se quer saber a minha opinião",
      "If you ask me, the old version was better.", "If you ask me, he should apologize.",
      "Sounds confident but still personal." },
    { "I'd say…", "Opinions", "A soft way to give an opinion or an estimate.", "Eu diria que…",
      "I'd say it takes about an hour.", "I'd say she's the best person for the job.",
      "Perfect for estimates: \"I'd say around fifty people\"." },
    { "I'm on the fence", "Opinions", "I haven't decided yet.", "Estou em cima do muro / indeciso",
      "I'm on the fence about buying a new car.", "She's still on the fence about the offer.",
      "Use \"about\" + the topic." },
    { "It's not my cup of tea", "Opinions", "It's not something I enjoy.", "Não é a minha praia",
      "Horror movies aren't really my cup of tea.", "Jazz is nice, but it's not my cup of tea.",
      "A polite way to say you don't like something." },
    { "I couldn't agree more", "Opinions", "I agree completely.", "Concordo plenamente",
      "— We need a break. — I couldn't agree more.", "I couldn't agree more with what you said.",
      "Sounds negative, but it means total agreement." },
    { "That's a good point", "Opinions", "Used to accept that someone's argument is good.", "Bem lembrado / bom argumento",
      "That's a good point. I hadn't thought of that.", "Okay, that's a good point, but it's still expensive.",
      "Great for meetings: it shows you're listening." },
    { "I see what you mean, but…", "Opinions", "A polite way to disagree.", "Entendo o seu ponto, mas…",
      "I see what you mean, but I think it's too risky.", "I see what you mean, but we don't have the budget.",
      "Disagree without sounding rude." },
    { "I'm not so sure about that", "Opinions", "A gentle way to say you disagree.", "Não tenho tanta certeza",
      "— It'll be easy. — Hmm, I'm not so sure about that.", "I'm not so sure about that plan.",
      "Softer than \"I disagree\"." },
    { "Fair enough", "Opinions", "That's reasonable; I accept it.", "Justo / tá certo",
      "— I can't come, I'm working. — Fair enough.", "Fair enough, let's do it your way.",
      "Very common in British and American English." },
    { "That makes sense", "Opinions", "That is logical; I understand.", "Faz sentido",
      "Oh, that makes sense now.", "Does that make sense?",
      "Classic mistake: never \"it does sense\". It's MAKE sense." },
    { "It's up to you", "Opinions", "You decide.", "Você que sabe / você decide",
      "Pizza or sushi? It's up to you.", "It's up to you whether we leave now or later.",
      "\"Up to me\" = I decide." },
    { "Either way", "Opinions", "In both cases; whatever happens.", "De qualquer jeito",
      "We can take the bus or walk. Either way, we'll be late.", "Either way, I'm happy.",
      "Good to show you're flexible." },

    -- Work
    { "Let's get started", "Work", "Let's begin.", "Vamos começar",
      "Okay everyone, let's get started.", "Let's get started with the first topic.",
      "Standard way to open a meeting." },
    { "I'll get back to you", "Work", "I'll answer later, after I check.", "Te dou um retorno",
      "Let me check my calendar and get back to you.", "I'll get back to you by Friday.",
      "Professional way to say \"I don't know yet\"." },
    { "Touch base", "Work", "Make brief contact to share updates.", "Alinhar rapidinho / dar uma atualizada",
      "Let's touch base next week.", "I just wanted to touch base about the project.",
      "Common in work emails." },
    { "On the same page", "Work", "Having the same understanding.", "Alinhados",
      "Let's make sure we're on the same page.", "Are we all on the same page?",
      "Use it before or after explaining a plan." },
    { "Keep me posted", "Work", "Keep me informed about any news.", "Me mantenha informado",
      "Keep me posted on the results.", "Thanks! Keep me posted.",
      "Friendly and professional at the same time." },
    { "Follow up on", "Work", "Check on something again later.", "Dar seguimento / retomar",
      "I'm following up on my last email.", "Can you follow up on that request?",
      "\"Just following up\" is the classic polite reminder." },
    { "I'm running late", "Work", "I'm going to arrive later than planned.", "Estou atrasado (a caminho)",
      "Sorry, I'm running late. Be there in ten.", "The train is running late today.",
      "Send this BEFORE you're late; it's polite." },
    { "Bring up", "Work", "Mention a subject.", "Levantar / mencionar (um assunto)",
      "I'd like to bring up something important.", "Don't bring up politics at dinner.",
      "Phrasal verb. Also means \"raise\" a child." },
    { "Look into", "Work", "Investigate or check something.", "Verificar / dar uma olhada",
      "I'll look into the problem today.", "We're looking into what happened.",
      "Promises action without promising a solution." },
    { "Call it a day", "Work", "Stop working for today.", "Encerrar por hoje",
      "It's late. Let's call it a day.", "We called it a day at six.",
      "Very common at the end of the workday." },
    { "The bottom line", "Work", "The most important point or result.", "No fim das contas / o principal",
      "The bottom line is we need more customers.", "What's the bottom line?",
      "Use it to cut to the main point." },
    { "A ballpark figure", "Work", "A rough estimate.", "Um número aproximado",
      "Can you give me a ballpark figure?", "Just a ballpark: around ten thousand.",
      "Shows you only need an estimate, not exact numbers." },
    { "Get the ball rolling", "Work", "Start something.", "Dar o pontapé inicial",
      "Let's get the ball rolling with a quick intro.", "Who wants to get the ball rolling?",
      "Common at the start of meetings and projects." },
    { "Learn the ropes", "Work", "Learn how a job or place works.", "Aprender como as coisas funcionam",
      "It took me a month to learn the ropes.", "She's still learning the ropes.",
      "Perfect for talking about a new job." },
    { "Have a lot on my plate", "Work", "Have many things to do.", "Estar cheio de coisas pra fazer",
      "I have a lot on my plate this week.", "Sorry, I've got too much on my plate right now.",
      "A polite way to say no to extra work." },

    -- Phrasal verbs
    { "Figure out", "Phrasal verb", "Understand or solve something.", "Entender / descobrir / resolver",
      "I can't figure out how this works.", "We'll figure it out together.",
      "One of the most useful phrasal verbs in daily life." },
    { "Come up with", "Phrasal verb", "Think of an idea or a plan.", "Ter (uma ideia) / bolar",
      "She came up with a great idea.", "We need to come up with a solution.",
      "Always \"come up WITH\" + the idea." },
    { "Deal with", "Phrasal verb", "Handle a problem, a task or a person.", "Lidar com",
      "I'll deal with it tomorrow.", "He's hard to deal with.",
      "Past: dealt with." },
    { "Sort out", "Phrasal verb", "Fix or organize something.", "Resolver / organizar",
      "Let's sort out the details later.", "I need to sort out my papers.",
      "Very common, especially in British English." },
    { "Put off", "Phrasal verb", "Postpone; do later.", "Adiar / enrolar",
      "Stop putting it off and just do it.", "They put off the meeting until Monday.",
      "Followed by -ing: \"put off doing\"." },
    { "Call off", "Phrasal verb", "Cancel.", "Cancelar",
      "They called off the game because of the rain.", "The wedding was called off.",
      "More natural than \"cancel\" in conversation." },
    { "Find out", "Phrasal verb", "Discover information.", "Descobrir / ficar sabendo",
      "I just found out she's moving.", "Let me find out what time it starts.",
      "Use it for information. For solving problems, \"figure out\"." },
    { "Catch up", "Phrasal verb", "Talk about recent news, or reach the same level.", "Colocar o papo em dia / alcançar",
      "Let's grab coffee and catch up.", "I missed a week, so I need to catch up.",
      "\"Catch up with someone\" = meet and talk." },
    { "Hang out", "Phrasal verb", "Spend time together casually.", "Sair / passar um tempo junto",
      "We hung out at the park all afternoon.", "Do you want to hang out this weekend?",
      "Informal and very common." },
    { "Show up", "Phrasal verb", "Arrive or appear, often unexpectedly.", "Aparecer",
      "He showed up an hour late.", "Only five people showed up.",
      "Used a lot when someone doesn't come: \"he didn't show up\"." },
    { "Turn down", "Phrasal verb", "Reject an offer; lower the volume.", "Recusar / abaixar",
      "She turned down the job offer.", "Can you turn down the music?",
      "Two very different meanings; context decides." },
    { "Give up", "Phrasal verb", "Stop trying.", "Desistir",
      "Don't give up, you're almost there.", "I gave up sugar last year.",
      "\"Give up + something\" = stop having it." },
    { "Get along with", "Phrasal verb", "Have a good relationship with someone.", "Se dar bem com",
      "I get along well with my coworkers.", "Do you get along with your brother?",
      "\"Get on with\" means the same in British English." },
    { "Look forward to", "Phrasal verb", "Feel happy about something that will happen.", "Estar ansioso por (no bom sentido)",
      "I'm looking forward to seeing you.", "We look forward to your reply.",
      "Classic trap: TO + -ing. \"Looking forward to SEEING\", not \"to see\"." },
    { "Run out of", "Phrasal verb", "Have no more of something.", "Ficar sem / acabar",
      "We ran out of coffee.", "I'm running out of time.",
      "The thing that ends comes after \"of\"." },
    { "End up", "Phrasal verb", "Finally be in a situation you didn't plan.", "Acabar (fazendo / em algum lugar)",
      "We ended up staying until midnight.", "He ended up in Canada.",
      "Followed by -ing or a place." },
    { "Work out", "Phrasal verb", "Exercise; or have a good result.", "Malhar / dar certo",
      "I work out three times a week.", "Don't worry, it'll work out.",
      "\"It didn't work out\" = it failed (also for relationships)." },
    { "Make up your mind", "Phrasal verb", "Decide.", "Se decidir",
      "Make up your mind, we're leaving!", "I can't make up my mind.",
      "Change the pronoun: my mind, her mind, their mind." },
    { "Give it a try", "Phrasal verb", "Try something.", "Tentar / experimentar",
      "I've never surfed, but I'll give it a try.", "Give it a try, you might like it.",
      "\"Give it a shot\" means the same." },
    { "Count me in", "Phrasal verb", "Include me; I want to participate.", "Pode contar comigo",
      "Pizza tonight? Count me in!", "If you need help, count me in.",
      "Opposite: \"Count me out\"." },

    -- Reactions
    { "No way!", "Reactions", "Expresses surprise, or a strong no.", "Não acredito! / De jeito nenhum!",
      "— I got the job! — No way! Congrats!", "Lend him my car? No way.",
      "Tone of voice decides if it's surprise or refusal." },
    { "Good for you!", "Reactions", "I'm happy about your success.", "Que bom pra você!",
      "You finished the marathon? Good for you!", "— I quit smoking. — Good for you!",
      "Sincere when said warmly." },
    { "That's a shame", "Reactions", "That's sad or disappointing.", "Que pena",
      "You can't come? That's a shame.", "It's a shame the store closed.",
      "\"What a shame\" works too." },
    { "Tell me about it", "Reactions", "I know exactly what you mean (about something bad).", "Nem me fala",
      "— This traffic is terrible. — Tell me about it.", "— Mondays are so long. — Tell me about it!",
      "It does NOT mean \"tell me more\"." },
    { "Same here", "Reactions", "Me too.", "Eu também / idem",
      "— I'm starving. — Same here.", "— I loved the show. — Same here!",
      "Informal and quick." },
    { "You bet", "Reactions", "Certainly; also an answer to \"thank you\".", "Com certeza / imagina",
      "— Are you coming? — You bet!", "— Thanks for the help. — You bet.",
      "Very American." },
    { "Fingers crossed", "Reactions", "I'm hoping for good luck.", "Torcendo / dedos cruzados",
      "My interview is tomorrow. Fingers crossed!", "Fingers crossed it doesn't rain.",
      "People sometimes cross their fingers while saying it." },
    { "Sounds good", "Reactions", "I agree with the plan.", "Fechado / beleza",
      "— Meet at seven? — Sounds good.", "Sounds good to me!",
      "The most common way to accept a plan." },
    { "My bad", "Reactions", "It was my mistake (informal).", "Foi mal",
      "Oops, my bad. I'll fix it.", "My bad, I sent the wrong file.",
      "Only in casual situations." },
    { "No worries", "Reactions", "It's okay; don't worry.", "Sem problemas / tranquilo",
      "— Sorry I'm late. — No worries.", "— Thanks! — No worries.",
      "Also a relaxed answer to \"thank you\"." },
    { "Never mind", "Reactions", "Forget it; it isn't important.", "Deixa pra lá",
      "Never mind, I found my keys.", "What did you say? — Never mind.",
      "Different from \"don't worry\": it cancels what you said." },
    { "It's no big deal", "Reactions", "It isn't important or serious.", "Não é nada demais",
      "I forgot the snacks? It's no big deal.", "Don't worry, it's not a big deal.",
      "Use it to calm someone down." },
    { "I'll take your word for it", "Reactions", "I believe you without checking.", "Vou acreditar em você",
      "The soup is too spicy? I'll take your word for it.", "Fine, I'll take your word for it.",
      "Often a little humorous." },

    -- Polite requests
    { "Would you mind…?", "Polite requests", "A very polite way to ask for something.", "Você se importaria de…?",
      "Would you mind closing the window?", "Would you mind if I sat here?",
      "Followed by -ing. To say yes, answer \"Not at all\"!" },
    { "Could you do me a favor?", "Polite requests", "Asking someone for help.", "Pode me fazer um favor?",
      "Could you do me a favor and hold this?", "Could you do me a favor? I need a ride.",
      "\"Do\" a favor, never \"make\" a favor." },
    { "I was wondering if…", "Polite requests", "A very polite way to ask a question or a favor.", "Eu queria saber se…",
      "I was wondering if you could help me.", "I was wondering if you're free on Friday.",
      "Past tense makes it softer, not past." },
    { "Do you happen to know…?", "Polite requests", "Asking for information in a light way.", "Por acaso você sabe…?",
      "Do you happen to know where the station is?", "Do you happen to know her number?",
      "Great for talking to strangers." },
    { "Mind if I…?", "Polite requests", "Asking permission casually.", "Você se importa se eu…?",
      "Mind if I join you?", "Mind if I open the window?",
      "Short for \"Do you mind if I…?\"." },
    { "Sorry to bother you", "Polite requests", "Used before interrupting someone.", "Desculpa incomodar",
      "Sorry to bother you, but do you have a minute?", "Sorry to bother you again.",
      "Opens almost any request politely." },
    { "Could you say that again?", "Polite requests", "Please repeat.", "Pode repetir?",
      "Sorry, could you say that again?", "Could you say that again, a bit slower?",
      "Much better than \"What?\"." },
    { "I didn't catch that", "Polite requests", "I didn't hear or understand what you said.", "Não peguei / não entendi",
      "Sorry, I didn't catch that.", "I didn't catch your name.",
      "Native speakers say this constantly; use it without fear." },
    { "What's the word for…?", "Polite requests", "Asking for a word you don't remember.", "Qual é a palavra para…?",
      "What's the word for the thing you open wine with?", "Oh, what's the word… a corkscrew!",
      "A lifesaver: describe the thing and ask." },
    { "What do you mean by…?", "Polite requests", "Asking someone to explain a word or idea.", "O que você quer dizer com…?",
      "What do you mean by \"soon\"?", "What do you mean by that?",
      "Not \"what do you want to say\"." },

    -- Time and plans
    { "In the meantime", "Time & plans", "While waiting for something else.", "Enquanto isso",
      "The doctor is coming. In the meantime, sit down.", "Dinner's at eight. In the meantime, let's relax.",
      "Also \"meanwhile\"." },
    { "Sooner or later", "Time & plans", "At some time in the future; inevitably.", "Mais cedo ou mais tarde",
      "Sooner or later, you'll have to tell him.", "Everyone makes mistakes sooner or later.",
      "Same order as in Portuguese, easy to remember." },
    { "Every now and then", "Time & plans", "Sometimes, but not often.", "De vez em quando",
      "I eat fast food every now and then.", "Every now and then she calls me.",
      "\"From time to time\" means the same." },
    { "So far", "Time & plans", "Until now.", "Até agora",
      "So far, so good.", "How's the new job so far?",
      "Usually with present perfect: \"So far I've read two chapters\"." },
    { "At the last minute", "Time & plans", "Very late; just before the deadline.", "Em cima da hora",
      "He always does things at the last minute.", "They canceled at the last minute.",
      "\"Last-minute\" can describe things: a last-minute trip." },
    { "For the time being", "Time & plans", "For now; temporarily.", "Por enquanto",
      "I'm living with my parents for the time being.", "Let's leave it like this for the time being.",
      "A bit more formal than \"for now\"." },
    { "Let's play it by ear", "Time & plans", "Decide as things happen, without a fixed plan.", "Vamos ver na hora",
      "I don't know when we'll arrive. Let's play it by ear.", "No plans yet, we'll play it by ear.",
      "Great for relaxed plans." },
    { "Can I take a rain check?", "Time & plans", "Can we do it another time? (declining an invite)", "Fica pra próxima?",
      "I'm exhausted tonight. Can I take a rain check?", "Rain check on lunch? Something came up.",
      "A friendly way to say no now, yes later." },
    { "Can you make it?", "Time & plans", "Are you able to come?", "Você consegue ir?",
      "The party's on Saturday. Can you make it?", "Sorry, I can't make it tomorrow.",
      "\"Make it\" also means \"succeed\": we made it!" },
    { "Ahead of time", "Time & plans", "Before the planned time; in advance.", "Com antecedência",
      "Let me know ahead of time if you're coming.", "We finished ahead of time.",
      "\"In advance\" means the same." },
    { "On time / in time", "Time & plans", "On time = at the planned time. In time = early enough.", "Pontualmente / a tempo",
      "The train left on time.", "We got there just in time for dinner.",
      "Two different ideas that Portuguese often mixes." },
    { "Take your time", "Time & plans", "There's no hurry.", "Sem pressa / fique à vontade",
      "Take your time, I'll wait.", "Take your time to decide.",
      "Kind and polite." },

    -- Idioms
    { "Piece of cake", "Idiom", "Very easy.", "Moleza",
      "The test was a piece of cake.", "Don't worry, it's a piece of cake.",
      "Very common in everyday talk." },
    { "Break the ice", "Idiom", "Make people feel relaxed when they first meet.", "Quebrar o gelo",
      "He told a joke to break the ice.", "A quick game helps break the ice.",
      "Same image as in Portuguese." },
    { "Under the weather", "Idiom", "A little sick.", "Meio indisposto / meio doente",
      "I'm feeling a bit under the weather today.", "She stayed home; she's under the weather.",
      "Used for mild sickness, like a cold." },
    { "Cut corners", "Idiom", "Do something badly or cheaply to save time or money.", "Fazer nas coxas / economizar onde não devia",
      "Don't cut corners on safety.", "They cut corners and the house had problems.",
      "Always negative." },
    { "Once in a blue moon", "Idiom", "Very rarely.", "Muito raramente",
      "I go to the movies once in a blue moon.", "He calls once in a blue moon.",
      "Fun and very common." },
    { "Beat around the bush", "Idiom", "Avoid saying the main point.", "Fazer rodeios / enrolar",
      "Stop beating around the bush and tell me.", "I won't beat around the bush: we lost the client.",
      "Use \"I won't beat around the bush\" before bad news." },
    { "Hit the nail on the head", "Idiom", "Say exactly the right thing.", "Acertar em cheio",
      "You hit the nail on the head with that comment.", "She hit the nail on the head.",
      "A strong way to agree." },
    { "Better late than never", "Idiom", "It's good that it happened, even if late.", "Antes tarde do que nunca",
      "You finally called! Better late than never.", "I started learning at 40. Better late than never.",
      "Same as the Portuguese saying." },
    { "Keep an eye on", "Idiom", "Watch or take care of something.", "Ficar de olho em",
      "Can you keep an eye on my bag?", "Keep an eye on the kids, please.",
      "Very practical in daily life." },
    { "It's not rocket science", "Idiom", "It isn't difficult.", "Não é nenhum bicho de sete cabeças",
      "Come on, it's not rocket science.", "Cooking rice isn't rocket science.",
      "Slightly informal." },
    { "Up in the air", "Idiom", "Not decided yet; uncertain.", "Indefinido / em aberto",
      "Our vacation plans are still up in the air.", "The date is up in the air.",
      "Use for plans and decisions." },
    { "On the bright side", "Idiom", "Looking at the positive part.", "Pelo lado bom",
      "It rained, but on the bright side, the garden loved it.", "On the bright side, we learned a lot.",
      "Good for staying positive in conversations." },
    { "In a nutshell", "Idiom", "In very few words.", "Em poucas palavras",
      "In a nutshell, the project was a success.", "That's the plan in a nutshell.",
      "Like \"long story short\", but more neutral." },
    { "Pull someone's leg", "Idiom", "Joke with someone by saying something untrue.", "Zoar / brincar com alguém",
      "Relax, I'm just pulling your leg.", "Are you pulling my leg?",
      "\"Are you kidding me?\" is similar." },
    { "Easier said than done", "Idiom", "It sounds easy but is hard to do.", "Falar é fácil",
      "Just relax? Easier said than done.", "Saving money is easier said than done.",
      "Perfect answer to simple advice for a hard problem." },
    { "Hit the road", "Idiom", "Leave; start a trip.", "Pegar a estrada / ir embora",
      "It's late, I should hit the road.", "We hit the road at six a.m.",
      "Casual way to say you're leaving." },
    { "The ball is in your court", "Idiom", "It's your turn to decide or act.", "A bola está com você",
      "I made my offer. The ball is in your court.", "Now the ball is in their court.",
      "Common in negotiations." },

    -- Feelings
    { "I'm fed up with…", "Feelings", "I'm tired and annoyed with something.", "Estou de saco cheio de…",
      "I'm fed up with this traffic.", "She's fed up with excuses.",
      "Followed by a noun or -ing." },
    { "I'm into…", "Feelings", "I really like (a hobby or topic).", "Eu curto… / estou ligado em…",
      "I'm really into photography these days.", "What kind of music are you into?",
      "Very natural for talking about interests." },
    { "I can't stand…", "Feelings", "I really hate it.", "Eu não suporto…",
      "I can't stand loud music in restaurants.", "She can't stand waiting.",
      "Followed by a noun or -ing." },
    { "It drives me crazy", "Feelings", "It annoys me a lot.", "Isso me deixa louco",
      "It drives me crazy when people are late.", "That noise is driving me crazy.",
      "Can also be positive in romance: \"you drive me crazy\"." },
    { "I'm over the moon", "Feelings", "I'm extremely happy.", "Estou nas nuvens",
      "She's over the moon about the baby.", "I was over the moon when I passed.",
      "Stronger than \"very happy\"." },
    { "Stressed out", "Feelings", "Very worried and tense.", "Estressado",
      "I'm so stressed out about the move.", "Don't get stressed out over small things.",
      "\"Out\" makes it stronger and more natural." },
    { "Get on my nerves", "Feelings", "Irritate me.", "Me irritar / me tirar do sério",
      "His jokes really get on my nerves.", "That sound is getting on my nerves.",
      "Change the pronoun: on her nerves, on our nerves." },
    { "I feel like…", "Feelings", "I want to (do something).", "Estou a fim de…",
      "I feel like having pizza tonight.", "I don't feel like going out.",
      "Followed by -ing. Not the same as \"I feel\"." },
    { "I can't wait", "Feelings", "I'm very excited about something coming.", "Mal posso esperar",
      "I can't wait for the weekend.", "I can't wait to see you!",
      "\"Can't wait FOR + noun\" or \"TO + verb\"." },
    { "It's worth it", "Feelings", "It deserves the time, money or effort.", "Vale a pena",
      "The trip was long, but it was worth it.", "Is it worth buying the bigger one?",
      "\"Worth + -ing\": it's worth trying." },
    { "There's no point in…", "Feelings", "It's useless to do it.", "Não adianta…",
      "There's no point in arguing.", "There's no point waiting, they're not coming.",
      "Followed by -ing." },

    -- Common mistakes (Brazilians)
    { "Actually", "Common mistakes", "In fact; to correct or add information.", "Na verdade",
      "Actually, I'm from Brazil, not Portugal.", "I thought it was hard, but actually it was easy.",
      "False friend: \"atualmente\" is \"currently\" or \"nowadays\"." },
    { "I'm used to…", "Common mistakes", "I'm accustomed to it.", "Estou acostumado a…",
      "I'm used to waking up early.", "You'll get used to it.",
      "Be used to + -ing. Different from \"I used to\" (past habit)." },
    { "I used to…", "Common mistakes", "Something I did regularly in the past, but not anymore.", "Eu costumava…",
      "I used to play soccer every day.", "She used to live in Rio.",
      "Only for the past. For now, say \"I usually\"." },
    { "Make a mistake", "Common mistakes", "Do something wrong.", "Cometer um erro",
      "Everyone makes mistakes.", "I made a mistake in the email.",
      "MAKE a mistake, never \"do a mistake\"." },
    { "Have a good time", "Common mistakes", "Enjoy yourself.", "Divirta-se",
      "Have a good time at the party!", "We had a great time.",
      "Not \"enjoy\" alone: say \"enjoy yourself\" or \"enjoy it\"." },
    { "Way too", "Common mistakes", "Much too; excessively.", "Demais (excessivamente)",
      "This coffee is way too sweet.", "I ate way too much.",
      "Informal; \"too\" already means excess, \"way\" makes it stronger." },
    { "How long have you been…?", "Common mistakes", "Asking for the duration until now.", "Há quanto tempo você…?",
      "How long have you been living here?", "How long have you been waiting?",
      "Not \"how long are you living here\". Use present perfect." },
    { "I agree", "Common mistakes", "I have the same opinion.", "Eu concordo",
      "I agree with you.", "I don't agree with that idea.",
      "Never \"I am agree\". Agree is a verb." },
    { "Pretend", "Common mistakes", "Act as if something is true when it isn't.", "Fingir",
      "He pretended to be asleep.", "Let's pretend we didn't see that.",
      "False friend: \"pretender\" is \"intend\" or \"plan\"." },
    { "Push / pull", "Common mistakes", "Push = move away from you. Pull = move toward you.", "Empurrar / puxar",
      "Push the door to open it.", "Pull the chair closer.",
      "Doors say PUSH or PULL; \"pull\" looks like \"puxe\" but don't trust it." },
}

local ARQ = DataStorage:getSettingsDir() .. "/lev_palavras.lua"
local dados -- progresso do quiz

local function abrirDados()
    if not dados then dados = LuaSettings:open(ARQ) end
    return dados
end

local function indiceDoDia(desloc)
    local t = os.time() + (desloc or 0) * 86400
    local d = os.date("*t", t)
    local seq = d.year * 366 + d.yday
    return (seq % #EXPRESSOES) + 1, t
end

local function entrada(i)
    local p = EXPRESSOES[i]
    return {
        palavra = p[1], classe = p[2], definicao = p[3], pt = p[4],
        exemplos = { p[5], p[6] }, dica = p[7],
    }
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
        width = largura, alignment = opts.alinhamento or "left", bold = opts.negrito,
        bgcolor = opts.fundo or BRANCO }
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
    local esp = function(n) return VerticalSpan:new{ width = Screen:scaleBySize(n) } end
    local g = VerticalGroup:new{ align = "left" }
    local quando = self.desloc == 0 and "Expression of the day" or os.date("Expression of %b %d", t)
    table.insert(g, TextWidget:new{ text = quando .. "  ·  " .. e.classe, face = face(15), fgcolor = CINZA })
    table.insert(g, esp(10))
    table.insert(g, caixa(e.palavra, 34, PRETO, larg, { face = face(34, true) }))
    table.insert(g, esp(14))
    table.insert(g, caixa(e.definicao, 21, PRETO, larg))
    table.insert(g, esp(8))
    table.insert(g, caixa("In Portuguese: " .. e.pt, 17, CINZA, larg))
    table.insert(g, esp(18))
    for _, ex in ipairs(e.exemplos) do
        table.insert(g, caixa("“" .. ex .. "”", 18, PRETO, larg, { face = face(18) }))
        table.insert(g, esp(8))
    end
    if e.dica and e.dica ~= "" then
        table.insert(g, esp(8))
        table.insert(g, FrameContainer:new{
            bordersize = Screen:scaleBySize(1), color = CLARO, background = BRANCO,
            radius = Screen:scaleBySize(10), padding = Screen:scaleBySize(12), width = larg,
            caixa("Tip: " .. e.dica, 16, CINZA, larg - Screen:scaleBySize(26)),
        })
    end
    table.insert(g, esp(22))
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

-- quiz: alterna "o que significa?" (opcoes em ingles) e "como se diz em ingles?" (mostra o portugues)
local semente = os.time()
local function aleatorio(n)
    semente = (semente * 1103515245 + 12345) % 2147483648
    return (semente % n) + 1
end

function TelaPalavra:abrirQuiz()
    local i = indiceDoDia(self.desloc)
    local certo = EXPRESSOES[i]
    local opcoes = { certo }
    local usados = { [i] = true }
    while #opcoes < 4 do
        local j = aleatorio(#EXPRESSOES)
        if not usados[j] then usados[j] = true; table.insert(opcoes, EXPRESSOES[j]) end
    end
    for k = #opcoes, 2, -1 do -- embaralha
        local r = aleatorio(k)
        opcoes[k], opcoes[r] = opcoes[r], opcoes[k]
    end
    local tipo = (aleatorio(2) == 1) and "significado" or "traducao"
    self.quiz = { certo = certo, opcoes = opcoes, resposta = nil, tipo = tipo }
    self.modo = "quiz"
    self:redesenhar()
end

function TelaPalavra:montarQuiz(W)
    local q = self.quiz
    local m = Screen:scaleBySize(28)
    local larg = W - 2 * m
    local g = VerticalGroup:new{ align = "left" }
    local traducao = q.tipo == "traducao"
    table.insert(g, TextWidget:new{ text = traducao and "Quiz · how do you say it in English?" or "Quiz · what does it mean?",
        face = face(15), fgcolor = CINZA })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    local pergunta = traducao and q.certo[4] or q.certo[1]
    table.insert(g, caixa(pergunta, 30, PRETO, larg, { face = face(30, true) }))
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(18) })
    for _, op in ipairs(q.opcoes) do
        local marcado = q.resposta ~= nil
        local e_certo = op == q.certo
        local escolhido = q.resposta == op
        local fundo = (marcado and e_certo) and PRETO or BRANCO
        local cor = (marcado and e_certo) and BRANCO or PRETO
        local prefixo = marcado and (e_certo and "✓  " or (escolhido and "✗  " or "")) or ""
        local texto = traducao and op[1] or op[3]
        local f = FrameContainer:new{
            bordersize = Screen:scaleBySize(1), color = escolhido and PRETO or CLARO, background = fundo,
            radius = Screen:scaleBySize(10), padding = Screen:scaleBySize(12), width = larg,
            caixa(prefixo .. texto, 17, cor, larg - Screen:scaleBySize(26), { fundo = fundo }),
        }
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
    if q.resposta then -- depois de responder, mostra o exemplo para fixar
        table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(4) })
        table.insert(g, caixa(q.certo[1] .. " = " .. q.certo[4] .. "\n“" .. q.certo[5] .. "”", 16, CINZA, larg))
    end
    local acertos = abrirDados():readSetting("acertos") or 0
    local tentativas = abrirDados():readSetting("tentativas") or 0
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(10) })
    table.insert(g, TextWidget:new{ text = string.format("Score: %d of %d", acertos, tentativas), face = face(14), fgcolor = CINZA })
    table.insert(g, VerticalSpan:new{ width = Screen:scaleBySize(16) })
    table.insert(g, HorizontalGroup:new{ align = "center",
        self:botao("‹ Back", function() self.modo = "palavra"; self:redesenhar() end),
        HorizontalSpan:new{ width = Screen:scaleBySize(10) },
        self:botao("Another", function() self:abrirQuizAleatorio() end),
    })
    return FrameContainer:new{ bordersize = 0, padding = m, padding_top = Screen:scaleBySize(30), background = BRANCO, g }
end

function TelaPalavra:abrirQuizAleatorio()
    self.desloc = -(aleatorio(30) - 1) -- hoje ou uma das ultimas ~30 expressoes
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
    self:redesenhar()
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
local P = { rotulo = "Expression of the day" }
function P.hoje()
    return entrada((indiceDoDia(0)))
end
function P.abrir()
    local M = rawget(_G, "__LEV_MODAL")
    local function mostrar()
        local tela = TelaPalavra:new{}
        UIManager:show(tela, "ui", tela.dimen)
    end
    if M and M.durante then M.durante("Loading…", mostrar) else mostrar() end
end
_G.__LEV_PALAVRA = P

logger.info("Lev: Expression of the day ativo,", #EXPRESSOES, "expressoes")
