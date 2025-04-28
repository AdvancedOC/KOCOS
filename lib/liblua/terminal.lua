local terminal = {}
local sys = require"syscalls"
local keyboard = require"keyboard"

function terminal.isatty()
    -- TODO: actually check once possible
    return true
end

function terminal.sendCSI(terminator, ...)
    checkArg(1, terminator, "string")
    local params = table.concat({...}, ";")
    assert(sys.write(0, "\x1b[" .. params .. terminator))
end

function terminal.clear()
    terminal.sendCSI("J", "2")
end

function terminal.setCursor(x, y)
    terminal.sendCSI("H", tostring(x), tostring(y))
end

function terminal.sendOSC(command, terminator)
    checkArg(1, command, "string")
    checkArg(2, terminator, "string", "nil")
    terminator = terminator or "\x1b\x5C"
    assert(sys.write(0, "\x1b]" .. command .. terminator))
end

function terminal.keyboardMode(enabled)
    terminal.sendCSI("i", enabled and "5" or "4")
end

local function parseTerm16(s)
    local t = {
        [":"] = "A",
        [";"] = "B",
        ["<"] = "C",
        ["="] = "D",
        [">"] = "E",
        ["?"] = "F",
    }
    return tonumber(string.gsub(s, ".", t), 16)
end

local escapePattern = "\x1b%[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]"
local paramPattern = "[\x30-\x3F]+"

---@type string[]
local escapesBuffer = {}

---@param nonblocking? boolean
---@return string?
function terminal.readEscape(nonblocking)
    if #escapesBuffer == 0 then
        while true do
            local data = sys.read(1, math.huge)
            for escape in string.gmatch(data, escapePattern) do
                table.insert(escapesBuffer, escape)
            end
            if data ~= "" or nonblocking then break end -- not waiting for data
            -- TODO: system yield
            coroutine.yield()
        end
    end
    return table.remove(escapesBuffer, 1)
end

function terminal.isShiftDown(modifiers)
    return bit32.btest(modifiers, 1)
end

function terminal.isAltDown(modifiers)
    return bit32.btest(modifiers, 2)
end

function terminal.isControlDown(modifiers)
    return bit32.btest(modifiers, 4)
end

function terminal.isSuperDown(modifiers)
    return bit32.btest(modifiers, 8)
end

-- Returns a parsed representation of an escape code
---@param nonblocking? boolean
---@return string?, ...
function terminal.queryEvent(nonblocking)
    local escape = terminal.readEscape(nonblocking)
    if not escape then return end -- no escapes to parse
    local term = escape:sub(-1, -1)
    local param = string.match(escape, paramPattern)

    local lib = unicode or string

    if term == "R" then
        -- response
        return "response", param
    end
    if term == "|" then
        local n = parseTerm16(param)
        local mod = n % 16
        n = math.floor(n / 16)
        -- Mimics OC key_down events
        return "key_down", "terminal", n, keyboard.charToCode(n) or 0, mod
    end
    if term == "\\" then
        local n = parseTerm16(param)
        local mod = n % 16
        n = math.floor(n / 16)
        -- Mimics OC key_down events
        return "key_down", "terminal", 0, n, mod
    end
    return "unknown", escape
end

---@return string
function terminal.getResponse()
    while true do
        local e, resp = terminal.queryEvent()
        if e == "response" then
            return resp
        end
        coroutine.yield()
    end
end

function terminal.getResolution()
    terminal.sendCSI("n", "5")
    local resp = terminal.getResponse()
    local parts = string.split(resp, ';')
    return tonumber(parts[1]), tonumber(parts[2])
end

function terminal.maxResolution()
    terminal.sendCSI("n", "7")
    local resp = terminal.getResponse()
    local parts = string.split(resp, ';')
    return tonumber(parts[1]), tonumber(parts[2])
end

-- Sends a KG OS command, which is used to perform raw draw operations.
-- More accurately, this powers set, fill and copy.
-- setForeground and setBackground use CSI 38 and 48 m.
function terminal.sendGraphicsCommand(cmd, ...)
    local args = table.concat({cmd, ...}, "\t")
    terminal.sendOSC("KG" .. args)
end

-- Sends a KT OS command, which is used to modify theme information.
-- More accurately, this powers setAnsiColor and setByteColor.
function terminal.sendThemeCommand(cmd, ...)
    local args = table.concat({cmd, ...})
    terminal.sendOSC("KT" .. args)
end

local function rgbSplit(c)
    local b = c % 256
    local g = math.floor(c / 256) % 256
    local r = math.floor(c / 65536) % 256
    return r, g, b
end

---@param c string
function terminal.setForeground(c)
    local r, g, b = rgbSplit(c)
    terminal.sendCSI("m", "38", "2", r, g, b)
end

---@param c string
function terminal.setBackground(c)
    local r, g, b = rgbSplit(c)
    terminal.sendCSI("m", "48", "2", r, g, b)
end

function terminal.set(x, y, s)
    terminal.sendGraphicsCommand("set", tostring(x), tostring(y), s)
end

function terminal.fill(x, y, w, h, s)
    terminal.sendGraphicsCommand("fill", tostring(x), tostring(y), tostring(w), tostring(h), s)
end

function terminal.copy(x, y, w, h, tx, ty)
    terminal.sendGraphicsCommand("copy", tostring(x), tostring(y), tostring(w), tostring(h), tostring(tx), tostring(ty))
end

function terminal.setResolution(w, h)
    terminal.sendGraphicsCommand("setResolution", tostring(w), tostring(h))
end

function terminal.reset()
    terminal.sendCSI("m", "0")
end

function terminal.invert()
    terminal.sendCSI("m", "7")
end

---@param n integer
---@param l? integer
function terminal.toHex(n, l)
    local s = ""
    local alpha = "0123456789ABCDEF"

    while n > 0 do
        local c = n % 16
        n = math.floor(n / 16)
        s = s .. alpha:sub(c+1, c+1)
    end

    if #s == 0 then s = "0" end

    s = s:reverse()
    if l and #s < l then
        s = string.rep("0", l - #s) .. s
    end
    return s
end

---@param entry integer
---@param color integer
function terminal.setAnsiColor(entry, color)
    terminal.sendThemeCommand("A", terminal.toHex(entry, 2), terminal.toHex(color))
end

function terminal.resetAnsiColors()
    terminal.sendThemeCommand("A", "R")
end

---@param entry integer
---@param color integer
function terminal.setByteColor(entry, color)
    terminal.sendThemeCommand("B", terminal.toHex(entry, 2), terminal.toHex(color))
end

function terminal.resetByteColors()
    terminal.sendThemeCommand("B", "R")
end

function terminal.hide()
    terminal.sendCSI("m", "8")
end

function terminal.show()
    terminal.sendCSI("m", "28")
end

function terminal.readPassword(prompt)
    if prompt then
        sys.write(0, prompt)
    end
    terminal.hide()
    local line = io.read("l")
    terminal.show()
    return line
end

return terminal
