local path = assert(arg[1], "no file path")
local terminal = require("terminal")
local keyboard = require("keyboard")

local w, h = terminal.getResolution()

local ox, oy = 0, 0
local cx, cy = 1, 1

local function hideCursor()
    terminal.reset()
    terminal.set(cx, cy, "")
end

local function showCursor()
    terminal.reset()
    terminal.invert()
    terminal.set(cx, cy, "")
end

local lines = {}

local function getFileContents()
    local f = assert(io.open(path, "rb"))
    for line in f:lines() do
        table.insert(lines, line)
    end
end

getFileContents()

terminal.clear()

for i=1,h-1 do
    terminal.set(1, i, lines[i] or "")
end

showCursor()

while true do
    terminal.reset()
    terminal.invert()
    terminal.fill(1, h, w, 1, " ")
    terminal.set(1, h, string.format("%d %d %s | q to quit", cx+ox, cy+oy, path))
    terminal.reset()

    terminal.keyboardMode(true)
    local event, _, char, code, mods = terminal.queryEvent()
    if event == "key_down" then
        if code == keyboard.keys.up then
            hideCursor()
            cy = cy - 1
            if cy == 0 then
                if cy+oy < 1 then
                    cy = 1
                else
                    terminal.copy(1, 1, w, h-2, 0, 1)
                    cy = 1
                    oy = oy - 1
                    terminal.fill(1, cy, w, 1, " ")
                    terminal.set(1, cy, (lines[cy+oy] or ""):sub(ox+1))
                end
            end
            showCursor()
        end
        if code == keyboard.keys.down then
            hideCursor()
            cy = cy + 1
            if cy == h then
                terminal.copy(1, 1, w, h-1, 0, -1)
                cy = h - 1
                oy = oy + 1
                terminal.fill(1, cy, w, 1, " ")
                terminal.set(1, cy, (lines[cy+oy] or ""):sub(ox+1))
            end
            showCursor()
        end
        if code == keyboard.keys.left then
            hideCursor()
            cx = cx - 1
            if cx == 0 then
                if cx+ox < 1 then
                    cx = 1
                else
                    terminal.copy(1, 1, w, h-1, 1, 0)
                    cx = 1
                    ox = ox - 1
                    terminal.fill(1, 1, 1, h-1, " ")
                    for j=1, h-1 do
                        terminal.set(1, j, (lines[j+oy] or ""):sub(ox+1))
                    end
                end
            end
            showCursor()
        end
        if code == keyboard.keys.right then
            hideCursor()
            cx = cx + 1
            if cx > w then
                terminal.copy(2, 1, w, h-1, -1, 0)
                cx = w
                ox = ox + 1
                terminal.fill(w, 1, 1, h-1, " ")
                for j=1, h-1 do
                    terminal.set(1, j, (lines[j+oy] or ""):sub(ox+1))
                end
            end
            showCursor()
        end
        if code == keyboard.keys.q then
            terminal.keyboardMode(false)
            terminal.reset()
            terminal.clear()
            return 0
        end
    end
    coroutine.yield()
end
