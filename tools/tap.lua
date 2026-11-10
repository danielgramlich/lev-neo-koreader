-- Simulated tap on the ELAN touchscreen: ./luajit tap.lua <x> <y> [seconds]  (portrait screen coords, 758x1024)
local sx, sy, segurar = tonumber(arg[1]), tonumber(arg[2]), tonumber(arg[3] or "0.1")
local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32(n) if n < 0 then n = n + 4294967296 end return u16(n % 65536) .. u16(math.floor(n / 65536)) end
local function ev(t, c, v) return u32(os.time()) .. u32(0) .. u16(t) .. u16(c) .. u32(v) end
local rx, ry = sy, 757 - sx -- inverso de adjustTouchSwitchAxesAndMirrorX
local f = assert(io.open("/dev/input/event2", "wb"))
f:write(ev(3, 0x30, 8) .. ev(3, 0x39, 1) .. ev(3, 0x35, rx) .. ev(3, 0x36, ry) .. ev(0, 2, 0) .. ev(0, 0, 0)); f:flush()
os.execute("busybox usleep " .. math.floor(segurar * 1000000))
f:write(ev(3, 0x30, 0) .. ev(0, 2, 0) .. ev(0, 0, 0)); f:flush(); f:close()
