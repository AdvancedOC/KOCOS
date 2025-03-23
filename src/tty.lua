local tty = {}
tty.__index = tty

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
    }, tty)
end

function tty:clear()
    self.x = 1
    self.y = 1
    self.gpu.fill(1, 1, self.w, self.h, " ")
end

function tty:put(c)
    if self.y > self.h then
        self.y = self.h
        self.gpu.copy(1, 1, self.w, self.h, 0, -1)
        self.gpu.fill(1, self.h, self.w, 1, " ")
    end

    if c == "\n" then
        self.y = self.y + 1
        self.x = 1
    elseif c == "\t" then
        self.x = self.x + 4
    else
        self.gpu.set(self.x, self.y, c)
        self.x = self.x + 1
    end

    if self.x > self.w then
        self.x = 1
        self.y = self.y + 1
    end
end

function tty:write(data)
    for i=1,#data do
        self:put(data:sub(i, i))
    end
end

function tty:print(fmt, ...)
    self:write(string.format(fmt, ...))
end

KOCOS.tty = tty

KOCOS.log("TTY subsystem loaded")
