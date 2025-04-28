-- Extremely bad radio chat
local terminal = require("terminal")
local keyboard = require("keyboard")
local keys = keyboard.keys

local KOCOS = _K
io.write("Name: ")
local name = io.read("l") or "Random"
io.write("Port: ")
local port = tonumber(io.read("l") or "") or 1

local radio = KOCOS.radio

if not radio.isOpen(port) then
    assert(radio.open(port))
end

local w, h = terminal.getResolution()

terminal.clear()

local chatOff = 1

while true do
    terminal.reset()
    terminal.invert()
    terminal.fill(1, 1, w, 1, " ")
    terminal.set(1, 1, string.format("Name: %s Port: %d | q to quit, tab to write message", name, port))

    do -- Handle radio messages
        local ok, sender, _, data, distance, time = radio.pop(port)
        if ok then
            if chatOff == h then
                terminal.copy(1, 3, w, h-2, 0, -1)
                terminal.fill(1, h, w, 1, " ")
            else
                chatOff = chatOff + 1
            end
            terminal.set(1, chatOff, string.format("(%.2fm) %s", distance, data))
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
                return 0
            end
            if code == keys.tab then
                terminal.reset()
                terminal.setCursor(1, 1) -- we put it at the top and hope
                terminal.fill(1, 1, w, 1, " ")
                local line = io.read("l")
                radio.send(radio.ADDR_BROADCAST, port, string.format("%s > %s", name, line))
            end
        end
    end

    coroutine.yield()
end
