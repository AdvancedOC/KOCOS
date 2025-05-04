-- Extremely bad radio chat
local terminal = require("terminal")
local keyboard = require("keyboard")
local sys = require("syscalls")
local keys = keyboard.keys

io.write("Name: ")
local name = io.read("l") or "Random"
io.write("Port: ")
local port = tonumber(io.read("l") or "") or 1

local client = assert(sys.socket("radio", "packet"))

assert(sys.connect(client, "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF", {port = 1}))

local w, h = terminal.getResolution()

terminal.clear()

local chatOff = 1

local function writePacket(data)
    if data == "" then return end
    terminal.reset()
    if chatOff == h then
        terminal.copy(1, 3, w, h-2, 0, -1)
        terminal.fill(1, h, w, 1, " ")
    else
        chatOff = chatOff + 1
    end
    terminal.set(1, chatOff, string.format("%s", data))
end

local radioRequestPacket

while true do
    terminal.reset()
    terminal.invert()
    terminal.fill(1, 1, w, 1, " ")
    terminal.set(1, 1, string.format("Name: %s Port: %d | q to quit, tab to write message", name, port))

    do -- Handle radio messages
        if not radioRequestPacket then
            radioRequestPacket = sys.aio_read(client, math.huge)
        end

        if sys.queued(client, "packet") then
            local data = assert(sys.read(client, math.huge))
            writePacket(data)
            radioRequestPacket = nil
        end
    end

    do -- Handle keyboard input
        terminal.reset()
        terminal.keyboardMode(true)
        local event, _, char, code, mods = terminal.queryEvent(true)
        if event == "key_down" then
            if code == keys.q then
                terminal.reset()
                terminal.clear()
                terminal.keyboardMode(false)
                sys.close(client)
                return 0
            end
            if code == keys.tab then
                terminal.reset()
                terminal.keyboardMode(false)
                terminal.setCursor(1, 1) -- we put it at the top and hope
                terminal.fill(1, 1, w, 1, " ")
                local line = io.read("l")
                sys.write(client, string.format("%s > %s", name, line))
            end
        end
    end

    coroutine.yield()
end
