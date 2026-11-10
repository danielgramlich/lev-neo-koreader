-- Simulated hardware key press on the Lev (run on the device with KOReader's luajit):
--   ./luajit key.lua <code> [seconds]
-- Codes: 139 = Home, 407 = right side button (next page), 158 = left side button (previous page).
local code, hold = tonumber(arg[1]), tonumber(arg[2] or "0.15")
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) if n < 0 then n = n + 4294967296 end return u16(n % 65536) .. u16(math.floor(n / 65536)) end
local function ev(t, c, v) return u32(os.time()) .. u32(0) .. u16(t) .. u16(c) .. u32(v) end
local f = assert(io.open("/dev/input/event0", "wb"))
f:write(ev(1, code, 1) .. ev(0, 0, 0)); f:flush()
os.execute("busybox usleep " .. math.floor(hold * 1000000))
f:write(ev(1, code, 0) .. ev(0, 0, 0)); f:flush(); f:close()
