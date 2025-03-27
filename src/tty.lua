local tty = {}
tty.__index = tty

local lib = unicode or string

function tty.create(gpu, screen)
    gpu.bind(screen.address)
    local w, h = gpu.maxResolution()
    gpu.setResolution(w, h)
    return setmetatable({
        gpu = gpu,
        screen = screen,
        x = 1,
        y = 1,
        w = w,
        h = h,
        buffer = "",
    }, tty)
end

function tty:clear()
    self.x = 1
    self.y = 1
    self.gpu.fill(1, 1, self.w, self.h, " ")
end

function tty:flush()
        self.gpu.set(self.x - #self.buffer, self.y, self.buffer)
        self.buffer = ""
end

function tty:put(c)
    if self.y > self.h then
        self:flush()
        self.y = self.h
        self.gpu.copy(1, 1, self.w, self.h, 0, -1)
        self.gpu.fill(1, self.h, self.w, 1, " ")
    end

    if c == "\n" then
        self:flush()
        self.y = self.y + 1
        self.x = 1
    elseif c == "\t" then
        self.x = self.x + 4
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
