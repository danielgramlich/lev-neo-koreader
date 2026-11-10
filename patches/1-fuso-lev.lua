-- Lev Neo (2026-11-06): fuso horario.
-- O KOReader e iniciado sem a variavel TZ, entao mostrava a hora em UTC.
-- Le o fuso de /etc/TZ (padrao BRT3 = Brasilia, UTC-3, sem horario de verao).
-- Para desfazer: apague este arquivo (koreader/patches/1-fuso-lev.lua).
local ffi = require("ffi")
pcall(ffi.cdef, [[
int setenv(const char *name, const char *value, int overwrite);
void tzset(void);
]])
local fuso = "BRT3"
local f = io.open("/etc/TZ", "r")
if f then
    local v = f:read("*l")
    f:close()
    if v and v:match("%S") then fuso = v:gsub("%s+", "") end
end
ffi.C.setenv("TZ", fuso, 1)
ffi.C.tzset()
