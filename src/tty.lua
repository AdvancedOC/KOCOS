---@alias KOCOS.Palette {[integer]: integer}

---@class KOCOS.TTY
---@field x integer
---@field y integer
---@field w integer
---@field h integer
---@field gpu table
---@field keyboard string
---@field mtx KOCOS.Lock
---@field isCursorShown boolean
---@field cursorToggleTime number
---@field defaultFg integer
---@field defaultBg integer
---@field fg integer
---@field bg integer
---@field responses mail
---@field commands mail
---@field escape? string
---@field ansiPalette KOCOS.Palette
---@field color256 KOCOS.Palette
---@field buffer string
---@field conceal boolean
---@field keysDown {[integer]: boolean}
---@field readImmediate boolean
---@field boundTo? string
---@field completed? string
---@field activeBuffer integer
---@field blinking boolean
local tty = {}
tty.__index = tty

local lib = unicode or string

local function color(r, g, b)
    return r * 0x10000 + g * 0x100 + b
end

local stdClrs = {
    -- taken from https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
    -- Mix of VS Code and VGA.
    -- BG is auto-computed.
    [30] = color(0, 0, 0), -- black
    [31] = color(205, 49, 49), -- red
    [32] = color(13, 188, 121), -- green
    [33] = color(229, 229, 16), -- yellow
    [34] = color(36, 114, 200), -- blue
    [35] = color(188, 63, 188), -- magenta
    [36] = color(17, 168, 205), -- cyan
    [37] = color(229, 229, 229), -- white
    [90] = color(85, 85, 85), -- bright black (gray)
    [91] = color(255, 85, 85), -- bright red
    [92] = color(85, 255, 85), -- bright green
    [93] = color(255, 255, 85), -- bright yellow
    [94] = color(59, 142, 234), -- bright blue
    [95] = color(255, 85, 255), -- bright magenta
    [96] = color(85, 255, 255), -- bright cyan
    [97] = color(255, 255, 255), -- bright white
}

local color256 = {
    [0] = stdClrs[30],
    [1] = stdClrs[31],
    [2] = stdClrs[32],
    [3] = stdClrs[33],
    [4] = stdClrs[34],
    [5] = stdClrs[35],
    [6] = stdClrs[36],
    [7] = stdClrs[37],
    [8] = stdClrs[90],
    [9] = stdClrs[91],
    [10] = stdClrs[92],
    [11] = stdClrs[93],
    [12] = stdClrs[94],
    [13] = stdClrs[95],
    [14] = stdClrs[96],
    [15] = stdClrs[97],
}

for red=0,5 do
    for green=0,5 do
        for blue=0,5 do
            local code = 16 + (red * 36) + (green * 6) + blue
            local r, g, b = 0, 0, 0
            if red ~= 0 then r = red * 40 + 55 end
            if green ~= 0 then g = green * 40 + 55 end
            if blue ~= 0 then b = blue * 40 + 55 end
            color256[code] = color(r, g, b)
        end
    end
end

for gray=0, 23 do
    local level = gray * 10 + 8
    local code = 232 + gray
    color256[code] = color(level, level, level)
end

local MAXBUFFER = 64*1024
local TOGGLE_INTERVAL = 0.5

function tty.create(gpu, keyboard, config)
    config = config or {}
    local w, h = 0, 0
    if gpu.type == "gpu" then
        w, h = gpu.getResolution()
    end
    local t = setmetatable({
        x = 1,
        y = 1,
        w = w,
        h = h,
        gpu = gpu,
        keyboard = keyboard,
        mtx = KOCOS.lock.create(),
        isCursorShown = false,
        cursorToggleTime = math.random(0, 2),
        fg = stdClrs[37],
        bg = stdClrs[30],
        ansiPalette = table.copy(stdClrs),
        color256 = table.copy(color256),
        -- they have buffer limits to try to mitigate OOM attacks
        responses = mail.create(MAXBUFFER),
        escape = nil,
        buffer = "",
        conceal = false,
        keysDown = {},
        readImmediate = false,
        boundTo = config.boundTo,
        completed = nil,
        activeBuffer = 0,
        blinking = KOCOS.default(config.blinking, true),
    }, tty)
    t:reset()
    return t
end

function tty:setCursor(x, y)
    self:hideCursor()
    self.x = x
    self.y = y
end

function tty:flush()
    local l = lib.len(self.buffer)
    if l == 0 then return end
    self:sync()
    self:switchBuffer(0)
    self.gpu.set(self.x-l, self.y, self.buffer)
    self.buffer = ""
end

function tty:sync()
    if self.gpu.type == "gpu" then
        if not self.boundTo then return end
        if self.gpu.getScreen() ~= self.boundTo then
            self.gpu.bind(self.boundTo)
            self.gpu.setResolution(self.w, self.h)
            self.gpu.setForeground(self.fg)
            self.gpu.setBackground(self.bg)
        end
    end
end

function tty:cleanup()
    if self.gpu.type == "gpu" then
        self.gpu.freeAllBuffers()
    end
end

function tty:hideCursor()
    if self.isCursorShown then
        self:switchBuffer(0)
        local c = self.gpu.get(self.x, self.y)
        self.gpu.setForeground(self.fg)
        self.gpu.setBackground(self.bg)
        self.gpu.set(self.x, self.y, c)
    end
    self.isCursorShown = false
    self.cursorToggleTime = computer.uptime() + TOGGLE_INTERVAL
end

function tty:showCursor()
    if not self.isCursorShown then
        self:switchBuffer(0)
        local c = self.gpu.get(self.x, self.y)
        self.gpu.setForeground(self.bg)
        self.gpu.setBackground(self.fg)
        self.gpu.set(self.x, self.y, c)
    end
    self.isCursorShown = true
    self.cursorToggleTime = computer.uptime() + TOGGLE_INTERVAL
    self.gpu.setForeground(self.fg)
    self.gpu.setBackground(self.bg)
end

function tty:toggleCursor()
    if self.isCursorShown then
        self:hideCursor()
    else
        self:showCursor()
    end
end

function tty:setForeground(clr)
    self.fg = clr
    self:sync()
    self.gpu.setForeground(clr)
end

function tty:setBackground(clr)
    self.bg = clr
    self:sync()
    self.gpu.setBackground(clr)
end

function tty:reset()
    if self.gpu.type ~= "gpu" then return end
    self:setForeground(self.ansiPalette[37] or 0xFFFFFF)
    self:setBackground(self.ansiPalette[30] or 0x000000)
    self.conceal = false
end

---@param code integer
---@param c integer
function tty:setAnsiColor(code, c)
    if not self.ansiPalette[code] then return end
    self.ansiPalette[code] = c
end

---@param code integer
---@param c integer
function tty:setByteColor(code, c)
    if not self.color256[code] then return end
    self.color256[code] = c
end

function tty:lock()
    self.mtx:lock(math.huge)
end

function tty:unlock()
    self.mtx:unlock()
end

function tty:clear()
    if self.gpu.type ~= "gpu" then return end -- can't lol
    self.x = 1
    self.y = 1
    self:sync()
    self.gpu.fill(1, 1, self.w, self.h, " ")
end

function tty:doGraphicalAction(args)
    local function pop()
        return table.remove(args, 1) or 0
    end

    local action = pop()
    if action == 0 then
        self:reset()
    elseif action == 7 then
        local bg, fg = self.fg, self.bg
        self:setForeground(fg)
        self:setBackground(bg)
    elseif action == 8 then
        self.conceal = true
    elseif action == 28 then
        self.conceal = false
    elseif (action >= 30 and action <= 37) or (action >= 90 and action <= 97) then
        self:setForeground(self.ansiPalette[action])
    elseif action == 38 then
        local fg = self.fg
        local mode = pop()
        if mode == 2 then
            -- 24-bit
            local r = pop()
            local g = pop()
            local b = pop()
            fg = color(r, g, b)
        elseif mode == 5 then
            -- 8-bit
            local byte = pop()
            fg = self.color256[byte] or 0
        end
        self:setForeground(fg)
    elseif (action >= 40 and action <= 47) or (action >= 100 and action <= 107) then
        self:setBackground(self.ansiPalette[action-10])
    elseif action == 48 then
        local bg = self.bg
        local mode = pop()
        if mode == 2 then
            -- 24-bit
            local r = pop()
            local g = pop()
            local b = pop()
            bg = color(r, g, b)
        elseif mode == 5 then
            -- 8-bit
            local byte = pop()
            bg = self.color256[byte] or 0
        end
        self:setBackground(bg)
    end
end

-- https://en.wikipedia.org/wiki/ANSI_escape_code
---@param c string
function tty:processEscape(c)
    local start = self.escape:sub(1, 1)

    if start == '[' then
        -- Process as CSI
        local b = string.byte(c)
        if b < 0x40 or b > 0x7E then
            -- We dont check if its actually parameter or intermediate bytes, cuz we don't care
            self.escape = self.escape .. c
            return
        end
        -- Terminator!!!!
        local data = self.escape:sub(2)
        local paramLen = 0
        while paramLen < #data do
            local paramByte = data:byte(paramLen+1, paramLen+1)
            if paramByte < 0x30 or paramByte > 0x3F then break end
            paramLen = paramLen + 1
        end
        local params = data:sub(1, paramLen)
        local action = c

        self.escape = nil

        -- In terms of colors, we support the normal colors and 24-bit colors, but not 256 color mode yet.
        if action == "m" then
            local strArgs = string.split(params, ";")
            local args = {}
            for i=1,#strArgs do
                args[i] = tonumber(strArgs[i]) or 0
            end
            if #args == 0 then args = {0} end
            while #args > 0 do
                self:doGraphicalAction(args)
            end
        end

        if action == "H" then
            local strArgs = string.split(params, ";")
            local args = {}
            for i=1,#strArgs do
                args[i] = tonumber(strArgs[i]) or 0
            end
            local x = tonumber(args[1] or "") or 1
            local y = tonumber(args[2] or "") or 1

            x = math.clamp(x, 1, self.w)
            y = math.clamp(y, 1, self.h)

            self.x = x
            self.y = y
        end

        if action == "J" then
            -- Only support full screen clearing for now
            if params == "2" then
                self:clear()
            end
        end

        if action == "K" then
            local y = self.y
            if params ~= "" then
                y = tonumber(params) or 1
            end
            self:switchBuffer(0)
            self.gpu.fill(1, y, self.w, 1, " ")
        end

        if action == "i" then
            if params == "5" then
                self.readImmediate = true
            end
            if params == "4" then
                self.readImmediate = false
            end
        end

        if action == "n" then
            -- standard
            if params == "6" then
                -- CSI 6n asks for a status report
                self.responses:push("\x1b[" .. tostring(self.x) .. ";" .. tostring(self.y) .. "R")
            end
            -- non-standard
            if params == "5" then
                self.responses:push("\x1b[" .. tostring(self.w) .. ";" .. tostring(self.h) .. "R")
            end
            if params == "7" then
                self:switchBuffer(0)
                local w, h = self.gpu.maxResolution()
                self.responses:push("\x1b[" .. tostring(w) .. ";" .. tostring(h) .. "R")
            end
            if params == "8" then
                -- VRAM stats
                self:switchBuffer(0)
                local free = self.gpu.freeMemory()
                local total = self.gpu.totalMemory()
                self.responses:push("\x1b[" .. tostring(math.floor(free or 0)) .. ";" .. tostring(math.floor(total or 0)) .. "R")
            end
        end
    elseif start == ']' then
        -- Process as OSC
        self.escape = self.escape .. c
        -- Bell, single character ST and full ST escape are the terminators.
        local terminators = {"\a", "\x9C", "\x1b\x5C"}
        ---@type string?
        local data = nil
        for _, terminator in ipairs(terminators) do
            if lib.sub(self.escape, -#terminator) == terminator then
                data = self.escape:sub(2, -#terminator - 1) -- from 2nd char (past ]) up until terminator
                break
            end
        end
        if data then
            local ok, err = pcall(self.runCommand, self, data)
            if not ok then
                KOCOS.log("TTY ERROR: %s", err)
                computer.beep()
            end
            self.escape = nil
        end
    end
end

---@param buffer integer
function tty:switchBuffer(buffer)
    self:sync()
    if self.gpu.type == "gpu" then
        self.activeBuffer = self.gpu.getActiveBuffer() or self.activeBuffer
        if self.activeBuffer ~= buffer then
            self.gpu.setActiveBuffer(buffer)
            self.gpu.setForeground(self.fg)
            self.gpu.setBackground(self.bg)
            self.activeBuffer = buffer
        end
    end
end

---@param s string
---@return string[]
local function ktArgSplit(s)
    local args = {}
    local buf = ""
    for i=1,#s do
        local c = s:sub(i, i)
        if c == "\t" then
            table.insert(args, buf)
            buf = ""
        else
            buf = buf .. c
        end
    end
    return args
end

function tty:runCommand(cmd)
    if cmd:sub(1,2) == "KG" then
        -- KOCOS Graphics command
        self:sync()
        local args = ktArgSplit(cmd:sub(3))
        local op = table.remove(args, 1)
        -- unrecognized is just a no-op
        if op == "set" then
            local x = tonumber(args[1]) or 1
            local y = tonumber(args[2]) or 1
            local s = args[3] or ""
            local b = tonumber(args[4]) or 0
            -- nice feature to overwrite just colors
            if #s == 0 then s = self.gpu.get(x, y) or " " end
            self:switchBuffer(b)
            assert(self.gpu.set(x, y, s))
        end
        if op == "get" then
            local x = tonumber(args[1]) or 1
            local y = tonumber(args[2]) or 1
            local b = tonumber(args[3]) or 0
            self:switchBuffer(b)
            local c, f, b = self.gpu.get(x, y)
            c = c or "\0"
            f = f or 0xFFFFFF
            b = b or 0

            local u = utf8.codepoint(c)
            self.responses:push("\x1b[" .. tostring(u) .. ";" .. tostring(f) .. ";" .. tostring(b) .. "R")
        end
        if op == "fill" then
            local x = tonumber(args[1]) or 1
            local y = tonumber(args[2]) or 1
            local w = tonumber(args[3]) or 1
            local h = tonumber(args[4]) or 1
            local s = args[5]
            local b = tonumber(args[6]) or 0
            if not s or #s == 0 then s = " " end
            self:switchBuffer(b)
            assert(self.gpu.fill(x, y, w, h, s))
        end
        if op == "copy" then
            local x = tonumber(args[1]) or 1
            local y = tonumber(args[2]) or 1
            local w = tonumber(args[3]) or 1
            local h = tonumber(args[4]) or 1
            local tx = tonumber(args[5]) or 0
            local ty = tonumber(args[6]) or 0
            local b = tonumber(args[7]) or 0
            self:switchBuffer(b)
            assert(self.gpu.copy(x, y, w, h, tx, ty))
        end
        if op == "setResolution" then
            local w = tonumber(args[1]) or self.w
            local h = tonumber(args[2]) or self.h
            self.gpu.setResolution(w, h)
            self.w = w
            self.h = h
        end
        if op == "getBufferSize" then
            local b = tonumber(args[1]) or 0
            local w, h = self.gpu.getBufferSize(b)
            if type(w) ~= "number" then w = "" end
            if type(h) ~= "number" then h = "" end
            self.responses:push("\x1b[" .. tostring(w) .. ";" .. tostring(h) .. "R")
        end
        if op == "memcpy" then
            local src = tonumber(args[1]) or 0
            local x = tonumber(args[2]) or 1
            local y = tonumber(args[3]) or 1
            local w = tonumber(args[4]) or self.w
            local h = tonumber(args[5]) or self.h
            local dst = tonumber(args[6]) or 0
            local dx = tonumber(args[7]) or 1
            local dy = tonumber(args[8]) or 1
            assert(self.gpu.bitblt(dst, dx, dy, w, h, src, x, y))
        end
        if op == "allocateBuffer" then
            local w = tonumber(args[1]) or self.w
            local h = tonumber(args[2]) or self.h
            local buf = self.gpu.allocateBuffer(w, h) or ""
            self.responses:push("\x1b[" .. tostring(buf) .. "R")
        end
        if op == "freeBuffer" then
            local b = tonumber(args[1]) or 0
            assert(self.gpu.freeBuffer(b))
        end
        if op == "freeAllBuffers" then
            assert(self.gpu.freeAllBuffers())
            self:switchBuffer(0)
        end
        return
    elseif cmd:sub(1,2) == "KT" then
        -- KOCOS Theme command
        local c = cmd:sub(3, 3)
        local entry = tonumber(cmd:sub(4, 5), 16) or -1
        local hex = tonumber(cmd:sub(6), 16) or 0x000000
        if c == "A" then
            if cmd:sub(4, 4) == "R" then
                -- Reset
                self.ansiPalette = table.copy(stdClrs)
                return
            end
            self:setAnsiColor(entry, hex)
        elseif c == "B" then
            if cmd:sub(4, 4) == "R" then
                -- Reset
                self.color256 = table.copy(color256)
                return
            end
            self:setByteColor(entry, hex)
        end
        return
    end
end

---@param c string
function tty:putc(c)
    if self.escape then
        -- Likely a TTY OOM attack.
        if #self.escape >= 8192 then
            self.escape = nil
            return
        end
        if #self.escape == 0 then
            -- We support CSI and OSC. Other ones are invalid
            if c == '[' then
                self.escape = '['
            elseif c == ']' then
                self.escape = ']'
            else
                -- Invalid
                self.escape = nil
            end
        else
            self:processEscape(c)
        end
        return
    end

    if c == "\x1b" then
        self:flush()
        self.escape = ""
        return
    end

    if self.conceal then
        return
    end

    if c == "\n" then
        self:flush()
        self.y = self.y + 1
        self.x = 1
    elseif c == "\t" then
        self:flush()
        self.x = self.x + 4
    elseif c:byte() == 0x07 then
        self:flush()
        computer.beep()
    elseif c:byte() == 0x08 then
        self:flush()
        self.x = self.x - 1
        if self.x == 0 then self.x = 1 end
    elseif c == "\r" then
        self:flush()
        self.x = 1
    elseif c == "\f" then
        self:flush()
        self.x = 1
        self.y = 1
    else
        self.buffer = self.buffer .. c
        self.x = self.x + 1
    end

    if self.x > self.w then
        self:flush()
        self.x = 1
        self.y = self.y + 1
    end

    if self.y > self.h then
        self:flush()
        self.y = self.h
        self:switchBuffer(0)
        self.gpu.copy(1, 1, self.w, self.h, 0, -1)
        self.gpu.fill(1, self.h, self.w, 1, " ")
    end
end

---@param buffer string
function tty:write(buffer)
    if self.gpu.type == "kocos" then
        assert(self.gpu.write(0, buffer))
        return
    end
    if self.completed then
        self.completed = self.completed .. buffer
        return
    end
    self:lock()
    local l = lib.len(buffer)
    for i=1,l do
        local c = lib.sub(buffer, i, i)
        self:putc(c)
    end
    self:flush()
    self:unlock()
end

function tty:print(f, ...)
    self:write(string.format(f, ...))
end

function tty:popKeyboardEvent()
    return KOCOS.event.popWhere(function(event, addr, char, code)
        if addr == self.keyboard then
            return true
        end
    end)
end

function tty:clearKeyboardEvent()
    return KOCOS.event.clear(function(event, addr, char, code)
        if addr == self.keyboard then
            return true
        end
    end)
end

---@param num integer
---@return string
local function paramBase16(num)
    local base = "0123456789:;<=>?"
    local s = ""
    while num > 0 do
        local n = num % #base
        num = math.floor(num / #base)
        s = s .. base:sub(n+1,n+1)
    end
    if s == "" then return "0" end
    return s:reverse()
end

tty.TTY_ALLOW_AUTOCOMPLETE = -1

---@param action integer
---@return string
function tty:read(action)
    if self.gpu.type == "kocos" then
        return self.gpu.read(1, action)
    end

    local response = self.responses:pop()
    if response then return response end

    if self.readImmediate then
        local event, _, char, code = self:popKeyboardEvent()
        if event == "key_down" then self.keysDown[code] = true end
        if event == "key_up" then self.keysDown[code] = nil end

        if event ~= "key_down" then return "" end

        -- KOCOS custom escape sequences cuz yeah
        local keys = KOCOS.keyboard.keys
        local mods = 0
        if self.keysDown[keys.lshift] then
            mods = mods + 1
        end
        if self.keysDown[keys.lmenu] then
            mods = mods + 2
        end
        if self.keysDown[keys.lcontrol] then
            mods = mods + 4
        end
        -- TODO: find some kind of meta key idk
        if self.keysDown[keys] then
            mods = mods + 8
        end
        local num = char
        local term = "|"
        if KOCOS.keyboard.isControl(char) then
            -- Send as code
            num = code
            term = "\\"
        end
        local s = "\x1b[" .. paramBase16(num * 16 + mods) .. term
        return s
    end

    self:lock()
    self:clearKeyboardEvent()

    -- Handle reading graphically
    self:hideCursor()
    local inputBuffer = ""
    local cursor
    if self.completed then
        local cx, cy = nil, nil
        for i=1,lib.len(self.completed) do
            local c = lib.sub(self.completed, i, i)
            if c == "\t" then
                cx = self.x
                cy = self.y
                cursor = i-1
            else
                self:putc(c)
                inputBuffer = inputBuffer .. c
            end
        end
        self:flush()
        self.x = cx or self.x
        self.y = cy or self.y
        self.completed = nil
    end
    local ex, ey = self.x, self.y
    local i = cursor or #inputBuffer
    if not self.blinking then
        self:showCursor()
    end
    while true do
        if self.cursorToggleTime <= computer.uptime() and not self.conceal and self.blinking then
            self:toggleCursor()
        end
        local event, _, char, code = self:popKeyboardEvent()

        if event == "key_down" then self.keysDown[code] = true end
        if event == "key_up" then self.keysDown[code] = nil end

        if event == "clipboard" then
            self:switchBuffer(0)
            local data = char:gsub('\n', ' ') -- TODO: make newlines somewhat supported
            if not self.conceal then
                self:hideCursor()
                for i=1,lib.len(data) do
                    self:putc(lib.sub(data, i, i))
                end
                self:flush()
                self:showCursor()
            end
            inputBuffer = inputBuffer .. data
            i = i + #data
        end

        if event == "key_down" then
            self:switchBuffer(0)
            if code == KOCOS.keyboard.keys.enter then
                if not self.conceal then
                    self:hideCursor()
                    self.x = ex
                    self.y = ey
                    self:putc('\n')
                    self:flush()
                end
                inputBuffer = inputBuffer .. "\n"
                break
            elseif code == KOCOS.keyboard.keys.d and self.keysDown[KOCOS.keyboard.keys.lcontrol] then
                if not self.conceal then
                    self:hideCursor()
                    self.x = ex
                    self.y = ey
                    self:hideCursor()
                    self:putc('\n')
                    self:flush()
                end
                inputBuffer = inputBuffer .. string.char(4)
                break
            elseif code == KOCOS.keyboard.keys.back and i > 0 then
                inputBuffer = lib.sub(inputBuffer, 1, i-1) .. lib.sub(inputBuffer, i+1)
                i = i - 1
                if not self.conceal then
                    self:hideCursor()
                    self.x = self.x - 1
                    if self.x < 1 then
                        self.x = self.w
                        self.y = math.max(self.y - 1, 1)
                    end
                    local sx, sy = self.x, self.y
                    for j=i+1, lib.len(inputBuffer) do
                        self:putc(lib.sub(inputBuffer, j, j))
                    end
                    self:flush()
                    self.gpu.set(self.x, self.y, ' ')
                    ex = self.x
                    ey = self.y
                    self.x = sx
                    self.y = sy
                    self:showCursor()
                end
            elseif code == KOCOS.keyboard.keys.up and action == tty.TTY_ALLOW_AUTOCOMPLETE and not self.conceal then -- conceal disables autocomplete
                self:hideCursor()
                self.x = ex
                self.y = ey
                for _=1, #inputBuffer do
                    self.x = self.x - 1
                    if self.x < 1 then
                        self.x = self.w
                        self.y = math.max(self.y - 1, 1)
                    end
                    self.gpu.set(self.x, self.y, ' ')
                end
                inputBuffer = "\x11"
                self.completed = ""
                break
            elseif code == KOCOS.keyboard.keys.down and action == tty.TTY_ALLOW_AUTOCOMPLETE and not self.conceal then -- conceal disables autocomplete
                self:hideCursor()
                self.x = ex
                self.y = ey
                for _=1, #inputBuffer do
                    self.x = self.x - 1
                    if self.x < 1 then
                        self.x = self.w
                        self.y = math.max(self.y - 1, 1)
                    end
                    self.gpu.set(self.x, self.y, ' ')
                end
                inputBuffer = "\x12"
                self.completed = ""
                break
            elseif code == KOCOS.keyboard.keys.left and not self.conceal then
                if i > 0 then
                    self:hideCursor()
                    i = i - 1
                    self.x = self.x - 1
                    if self.x < 1 then
                        self.x = self.w
                        self.y = math.max(self.y - 1, 1)
                    end
                    self:showCursor()
                end
            elseif code == KOCOS.keyboard.keys.right and not self.conceal then
                if i < #inputBuffer then
                    self:hideCursor()
                    i = i + 1
                    self:putc(inputBuffer:sub(i, i))
                    self:flush()
                    self:showCursor()
                end
            elseif code == KOCOS.keyboard.keys.tab and action == tty.TTY_ALLOW_AUTOCOMPLETE and not self.conceal then -- conceal disables autocomplete
                self:hideCursor()
                self.x = ex
                self.y = ey
                for _=1, #inputBuffer do
                    self.x = self.x - 1
                    if self.x < 1 then
                        self.x = self.w
                        self.y = math.max(self.y - 1, 1)
                    end
                    self.gpu.set(self.x, self.y, ' ')
                end
                inputBuffer = lib.sub(inputBuffer, 1, i) .. "\t" .. lib.sub(inputBuffer, i+1)
                self.completed = ""
                break
            elseif not KOCOS.keyboard.isControl(char) then
                local c = lib.char(char)
                inputBuffer = lib.sub(inputBuffer, 1, i) .. c .. lib.sub(inputBuffer, i+1)
                i = i + 1
                if not self.conceal then
                    self:hideCursor()
                    self:putc(c)
                    local x, y = self.x, self.y
                    for j=i+1, lib.len(inputBuffer) do
                        self:putc(lib.sub(inputBuffer, j, j))
                    end
                    self:flush()
                    ex = self.x
                    ey = self.y
                    self.x = x
                    self.y = y
                    self:showCursor()
                end
            end
        end
        KOCOS.yield()
    end

    self:unlock()
    return inputBuffer
end

KOCOS.tty = tty

if KOCOS.loggingTTY then
    local loggingTTY
    local kocos = component.list("kocos")()
    if kocos then
        loggingTTY = tty.create(component.proxy(kocos), "no keyboard")
    else
        local gpu = component.list("gpu")()
        local screen = component.list("screen")()
        component.invoke(gpu, "bind", screen)
        local keyboards = component.invoke(screen, "getKeyboards")
        loggingTTY = KOCOS.tty.create(component.proxy(gpu), keyboards[1] or "no keyboard", {
            boundTo = screen,
        })
        loggingTTY:clear()
    end
    assert(loggingTTY, "unable to create logging TTY")
    KOCOS.setLoggingTTY(loggingTTY)
end

KOCOS.log("TTY subsystem loaded")
