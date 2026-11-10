-- Lev Neo (2026-11-06): evita o aviso falso "Pasta atual ilegivel..." ao iniciar.
-- Camadas do ZenOS que embrulham a listagem de pastas as vezes perdem o sinal
-- "pasta legivel" e o KOReader mostra o aviso mesmo com a pasta lendo normal.
-- Aqui conferimos de verdade (lfs.dir): se a pasta abre, o aviso nao aparece;
-- se for mesmo ilegivel, o aviso continua aparecendo como antes.
-- Para desfazer: apague este arquivo (koreader/patches/2-pasta-lev.lua).
local FileChooser = require("ui/widget/filechooser")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local refresh_original = FileChooser.refreshPath
function FileChooser:refreshPath(...)
    local caminho = self.path
    if caminho and pcall(lfs.dir, caminho) then
        self.unreadable_path_warned = caminho -- pasta abre: nao avisar
    end
    return refresh_original(self, ...)
end

logger.info("Lev: aviso falso de pasta ilegivel desativado")
