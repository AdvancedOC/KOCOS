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

function tty.create(gpu, screen)
    gpu.bind(screen.address)
    local w, h = gpu.maxResolution()
    gpu.setResolution(w, h)
    local t = setmetatable({
        gpu = gpu,
        screen = screen,
        x = 1,
        y = 1,
        w = w,
        h = h,
        buffer = "",
        escape = nil,
        commands = {},
        responses = {},
        -- Aux Port is about keyboard input, not yet implemented
        auxPort = false,
        conceal = false,
        defaultFg = stdClrs[37],
        defaultBg = stdClrs[30],
        standardColors = table.copy(stdClrs),
    }, tty)
    t:setActiveColors(t.defaultFg, t.defaultBg)
    return t
end

function tty:clear()
    self.x = 1
    self.y = 1
    self.gpu.fill(1, 1, self.w, self.h, " ")
end

function tty:flush()
        self.gpu.set(self.x - lib.len(self.buffer), self.y, self.buffer)
        self.buffer = ""
end

function tty:getActiveColors()
    return self.gpu.getForeground(), self.gpu.getBackground()
end

function tty:setDefaultActiveColors(fg, bg)
    self.defaultFg = fg
    self.defaultBg = bg
end

function tty:setActiveColors(fg, bg)
    return self.gpu.setForeground(fg), self.gpu.setBackground(bg)
end

function tty:getColorDepth()
    return self.gpu.getDepth()
end

function tty:popCommand()
    return table.remove(self.commands, 1)
end

function tty:popResponse()
    return table.remove(self.responses, 1)
end

function tty:doGraphicalAction(args)
    local function pop()
        return table.remove(args, 1) or 0
    end

    local action = pop()
    if action == 0 then
        self.conceal = false
        self.auxPort = false
        self:setActiveColors(self.defaultFg, self.defaultBg)
    elseif action == 8 then
        self.conceal = true
    elseif action == 28 then
        self.conceal = false
    elseif (action >= 30 and action <= 37) or (action >= 90 and action <= 97) then
        local fg, bg = self:getActiveColors()
        fg = self.standardColors[action]
        self:setActiveColors(fg, bg)
    elseif action == 38 then
        local fg, bg = self:getActiveColors()
        local mode = pop()
        if mode == 2 then
            -- 24-bit
            local r = pop()
            local g = pop()
            local b = pop()
            fg = color(r, g, b)
        end
        self:setActiveColors(fg, bg)
    elseif (action >= 40 and action <= 47) or (action >= 100 and action <= 107) then
        local fg, bg = self:getActiveColors()
        bg = self.standardColors[action-10]
        self:setActiveColors(fg, bg)
    elseif action == 48 then
        local fg, bg = self:getActiveColors()
        local mode = pop()
        if mode == 2 then
            -- 24-bit
            local r = pop()
            local g = pop()
            local b = pop()
            bg = color(r, g, b)
        end
        self:setActiveColors(fg, bg)
    end
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

local function isControlCharacter(char)
	return type(char) == "number" and (char < 0x20 or (char >= 0x7F and char <= 0x9F))
end

function tty:handleChar(char, code)
    -- Keyboard disabled
    if not self.auxPort then return end
    -- KOCOS custom escape sequences cuz yeah
    local mods = 0
    local num = char
    local term = "|"
    if isControlCharacter(char) then
        -- Send as code
        num = code
        term = "\\"
    end
    local s = "\x1b[" .. paramBase16(num * 16 + mods) .. term
    table.insert(self.responses, s)
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
            self.gpu.fill(1, y, self.w, 1, " ")
        end

        if action == "i" then
            -- CSI 5i for ON and CSI 4i for OFF, though we let any invalid param also be off.
            self.auxPort = params == "5"
        end

        if action == "n" then
            -- standard
            if params == "6" then
                -- CSI 6n asks for a status report
                table.insert(self.responses, "\x1b[" .. tostring(self.x) .. ";" .. tostring(self.y) .. "R")
            end
            -- non-standard
            if params == "5" then
                table.insert(self.responses, "\x1b[" .. tostring(self.w) .. ";" .. tostring(self.h) .. "R")
            end
            if params == "7" then
                table.insert(self.responses, "\x1b[" .. tostring(self.gpu.address) .. ";" .. tostring(self.gpu.getScreen()) .. "R")
            end
        end
    elseif start == ']' then
        -- Process as OSC
        self.escape = self.escape .. c
        -- Bell, single character ST and full ST escape are the terminators.
        local terminators = {"\b", "\x9C", "\x1b\x5C"}
        ---@type string?
        local data = nil
        for _, terminator in ipairs(terminators) do
            if string.endswith(self.escape, terminator) then
                data = self.escape:sub(2, -#terminator - 1) -- from 2nd char (past ]) up until terminator
                break
            end
        end
        if data then
            table.insert(self.commands, data)
            self.escape = nil
        end
    end
end

function tty:put(c)
    if self.y > self.h then
        self:flush()
        self.y = self.h
        self.gpu.copy(1, 1, self.w, self.h, 0, -1)
        self.gpu.fill(1, self.h, self.w, 1, " ")
    end

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
        elseif #c > 0 then
            self:processEscape(c)
        end
        return
    end

    if self.conceal then
        if #self.buffer > 0 then self:flush() end
        return
    end

    if c == "\n" then
        self:flush()
        self.y = self.y + 1
        self.x = 1
    elseif c == "\t" then
        self:flush()
        self.x = self.x + 4
        self.x = math.floor(self.x / 4) * 4
    elseif c:byte() == 0x07 then
        self:flush()
        computer.beep() -- Bell beeps.
    elseif c:byte() == 0x08 then
        self:flush()
        self.x = self.x - 1
        if self.x == 0 then self.x = 1 end
    elseif c == "\r" then
        self:flush()
        self.x = 1
    elseif c == "\f" then
        self:flush()
        -- There is no next printer page, so we just move to top of screen
        self.x = 1
        self.y = 1
    elseif c == "\x1b" then
        self:flush()
        self.escape = ""
        return
    else
        self.buffer = self.buffer .. c
        self.x = self.x + 1
    end

    if self.x > self.w then
        self:flush()
        self.x = 1
        self.y = self.y + 1
    end
end

function tty:unput(c)
    if c == "\n" then
        -- Assume this never happens
        error("cant remove newline")
    end
    local w = c == "\t" and 4 or 1

    self.x = self.x - w
    self.gpu.set(self.x,self.y,string.rep(" ", w))
    if self.x == 0 then
        self.x = self.w
        self.y = self.y - 1
    end

    if self.y == 0 then
        self.y = 1
    end
end

function tty:write(data)
    for i=1,lib.len(data) do
        self:put(lib.sub(data, i, i))
    end
    self:flush()
end

function tty:unwrite(data)
    for i=lib.len(data), 1, -1 do
        self:unput(lib.sub(data, i, i))
    end
end

function tty:print(fmt, ...)
    self:write(string.format(fmt, ...))
end

KOCOS.tty = tty

KOCOS.log("TTY subsystem loaded")
