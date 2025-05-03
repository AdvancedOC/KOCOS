local gpu
local buffer

---@type gl.device
return {
    init = function(proxy)
        gpu = proxy or component.gpu
        buffer = gpu.allocateBuffer()
        gpu.setActiveBuffer(buffer)
    end,
    close = function()
        gpu.freeBuffer(buffer)
        gpu.setActiveBuffer(0)
    end,
    sync = function()
        gpu.bitblt()
    end,
    size = function()
        return gpu.getResolution()
    end,
    set = function(x, y, c, f, b)
        gpu.setForeground(f)
        gpu.setBackground(b)
        gpu.set(x, y, c)
    end,
}
