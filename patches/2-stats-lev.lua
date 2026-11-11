-- Lev Neo (2026-11-11): estatisticas do Inicio numa linha so.
-- Troca os tres numeros grandes (Pages today / Read today / Day streak) por uma linha
-- discreta: "13 pages · 14 min read today · 3-day streak". Mesmos dados do ZenOS.
-- Para desfazer: apague este arquivo (koreader/patches/2-stats-lev.lua).
local userpatch = require("userpatch")
local logger = require("logger")

local function face(tam)
    local ok, lf = pcall(require, "modules/filebrowser/patches/library_font")
    if ok and lf and lf.getFace then
        local ok2, f = pcall(lf.getFace, tam)
        if ok2 and f then return f end
    end
    return require("ui/font"):getFace("cfont", tam)
end

local function tempo(seg)
    seg = math.floor(tonumber(seg) or 0)
    local h, m = math.floor(seg / 3600), math.floor((seg % 3600) / 60)
    if h > 0 then return string.format("%d h %d min", h, m) end
    return string.format("%d min", m)
end

local function frase(st)
    local paginas = tonumber(st.today_pages) or 0
    local seq = tonumber(st.streak) or 0
    local partes = {
        paginas == 1 and "1 page" or string.format("%d pages", paginas),
        tempo(st.today_duration) .. " read today",
        seq > 0 and string.format("%d-day streak", seq) or "no streak yet",
    }
    return table.concat(partes, "  ·  ")
end

userpatch.registerPatchPluginFunc("zenos", function()
    local ok, Registry = pcall(require, "modules/filebrowser/patches/home/components/registry")
    local comp = ok and Registry and Registry.get and Registry.get("stats_triplet")
    if not comp or comp._lev_linha then
        if not comp then logger.warn("Lev stats: componente stats_triplet nao encontrado") end
        return
    end
    comp._lev_linha = true
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Geom = require("ui/geometry")
    local TextWidget = require("ui/widget/textwidget")
    local buildOriginal = comp.build
    comp.build = function(ctx, ...)
        local okL, w = pcall(function()
            local st = (ctx and ctx.data and ctx.data.stats) or {}
            return CenterContainer:new{
                dimen = Geom:new{ w = ctx.width, h = ctx.height },
                TextWidget:new{ text = frase(st), face = face(17), fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    max_width = ctx.width },
            }
        end)
        if okL and w then return w end
        logger.warn("Lev stats: erro, usando o original:", w)
        return buildOriginal(ctx, ...)
    end
    logger.info("Lev: estatisticas do Inicio numa linha")
end)
