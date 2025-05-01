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

---@type buffer?
local stream = assert(io.open(path, "rb"))
local chunkSize = 1024
local lineBuffer = ""

stream:seek("set", 0)

local function addLine(line)
    line = line:gsub(".", function(c)
        if not keyboard.isPrintable(c:byte()) then return "^@" end
        return c
    end)
    table.insert(lines, line)
    local i = #lines

    local y = i - oy
    if y >= 1 and y < h then
        terminal.set(1, y, line:sub(ox+1))
        if cy == y then
            showCursor()
            terminal.reset()
        end
    end
end

local function getMoreFileContents()
    if not stream then return end
    ---@type string?
    local chunk = stream:read(chunkSize)
    if not chunk then
        if #lineBuffer > 0 then addLine(lineBuffer) end
        stream:close()
        stream = nil
        return
    end
    lineBuffer = lineBuffer .. chunk
    while true do
        local lineFeed = lineBuffer:find("\n")
        if not lineFeed then break end -- need more data
        if lineFeed then
            local line = lineBuffer:sub(1, lineFeed-1)
            lineBuffer = lineBuffer:sub(lineFeed+1)
            addLine(line)
        end
    end
end

terminal.clear()

for i=1,h-1 do
    terminal.set(1, i, lines[i] or "")
end

showCursor()

while true do
    terminal.reset()
    terminal.invert()
    terminal.fill(1, h, w, 1, " ")
    terminal.set(1, h, string.format("%d %d %s | q to quit | %d lines", cx+ox, cy+oy, path, #lines))
    terminal.reset()

    getMoreFileContents()

    terminal.keyboardMode(true)
    local event, _, char, code, mods = terminal.queryEvent(true)
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
