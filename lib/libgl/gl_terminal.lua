local terminal = require("terminal")

local renderBuffer = terminal.allocateBuffer()

---@type gl.device
return {
    init = function()
        terminal.clear()
    end,
    set = function(x, y, c, f, b)
        terminal.setForeground(f)
        terminal.setBackground(b)
        terminal.set(x+1, y+1, c, renderBuffer)
    end,
    sync = function()
        terminal.memcpy(renderBuffer)
    end,
    size = terminal.getResolution,
    close = function()
        terminal.freeBuffer(renderBuffer)
    end,
}
