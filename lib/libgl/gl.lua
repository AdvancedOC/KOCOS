-- Heavily inspired by the raster library in HalydeOS.
-- If you like KOCOS' reference GL, check out https://github.com/Team-Cerulean-Blue/Halyde
local gl = {}

---@class gl.buffer
---@field w integer
---@field h integer
---@field data integer[]
---@field dirtyChunks {[integer]: boolean}

gl.PIXEL_PER_X = 2
gl.PIXEL_PER_Y = 4
gl.CHUNK_AREA = gl.PIXEL_PER_X * gl.PIXEL_PER_Y

-- Values between 0-255
-- Returns 0xRRGGBBAA
function gl.color(r, g, b, a)
    r = r or 0
    g = g or 0
    b = b or 0
    a = a or 255
    return a +
    b * 0x100 +
    g * 0x10000 +
    r * 0x1000000
end

---@return gl.buffer
function gl.newBuffer(w, h, color)
    color = color or 0
    local data = {}
    if color ~= 0 then
        for i=1, w * h do
            data[i] = color
        end
    end
    return {
        w = w,
        h = h,
        data = data,
        dirtyChunks = {},
    }
end

---@param buffer gl.buffer
function gl.computeChunk(buffer, x, y)
    local cx = math.floor((x - 1) / gl.PIXEL_PER_X)
    local cy = math.floor((y - 1) / gl.PIXEL_PER_Y)
    local cw = math.floor(buffer.w / gl.PIXEL_PER_X)

    return 1 + cx + cy * cw
end

---@param buffer gl.buffer
---@param chunk integer
---@return integer, integer
function gl.computeChunkSlot(buffer, chunk)
    local ci = chunk - 1

    local cw = math.floor(buffer.w / gl.PIXEL_PER_X)

    local x = ci % cw
    local y = math.floor(ci / cw)
    return x, y
end

---@param buffer gl.buffer
function gl.clear(buffer, color)
    color = color or 0
    for x=1, buffer.w do
        for y=1, buffer.h do
            if gl.get(buffer, x, y) ~= color then
                gl.set(buffer, x, y, color)
            end
        end
    end
end

---@param buffer gl.buffer
function gl.computeOffset(buffer, x, y)
    if x < 1 or x > buffer.w or y < 1 or y > buffer.h then return end
    return (x - 1) + (y - 1) * buffer.w
end

---@param buffer gl.buffer
function gl.get(buffer, x, y)
    local o = gl.computeOffset(buffer, x, y)
    if not o then return 0 end
    return buffer.data[o] or 0
end

---@param buffer gl.buffer
function gl.sample(buffer, x, y)
    x = math.map(x, 0, 1, 1, buffer.w)
    y = math.map(y, 0, 1, 1, buffer.h)
    return gl.get(buffer, x, y)
end

---@param buffer gl.buffer
function gl.set(buffer, x, y, color)
    local o = gl.computeOffset(buffer, x ,y)
    if not o then return false, "out of bounds" end
    if (buffer.data[o] or 0) == color then return true end
    buffer.data[o] = color
    local ci = gl.computeChunk(buffer, x, y)
    buffer.dirtyChunks[ci] = true
    return true
end

---@param buffer gl.buffer
function gl.fill(buffer, x, y, w, h, color)
    for px=x,x+w+1 do
        for py=y,y+h+1 do
            gl.set(buffer, px, py, color)
        end
    end
end

---@param buffer gl.buffer
function gl.fillCircle(buffer, x, y, r, color)
    for px=x-r, x+r do
        for py=y-r, y+r do
            local dSqr = (x - px) ^ 2 + (y - py) ^ 2
            if dSqr <= r^2 then
                gl.set(buffer, px, py, color)
            end
        end
    end
end

---@return string, integer, integer
function gl.computeChunkValue(buffer, cx, cy)
    local px = cx * gl.PIXEL_PER_X
    local py = cy * gl.PIXEL_PER_Y

    -- Use braille characters, idea taken from Halyde
    local offs = {
        0, 0,
        0, 1,
        0, 2,
        1, 0,
        1, 1,
        1, 2,
        0, 3,
        1, 3,
    }

    local colors = {}

    for i=1, #offs, 2 do
        local x = offs[i]
        local y = offs[i+1]
        local value = gl.get(buffer, 1 + x + px, 1 + y + py)
        value = math.floor(value / 256)
        table.insert(colors, value)
    end

    local sorted = {}
    for _, color in ipairs(colors) do
        local dupe = false
        for _, other in ipairs(sorted) do
            if color == other then
                dupe = true
                break
            end
        end
        if not dupe then
            table.insert(sorted, color)
        end
    end
    table.sort(sorted)

    local codepoint = 0x2800
    local midPoint = math.floor(gl.CHUNK_AREA / 2)
    local pivot = sorted[midPoint] or 0
    local fg = 0
    local fgc = 0
    local bg = 0
    local bgc = 0

    for i=1,gl.CHUNK_AREA do
        local c = colors[i]
        if c <= pivot then
            fg = fg + c
            fgc = fgc + 1
            codepoint = codepoint + 2 ^ (i - 1)
        else
            bg = bg + c
            bgc = bgc + 1
        end
    end

    fg = fgc == 0 and 0 or math.floor(fg / fgc)
    bg = bgc == 0 and 0 or math.floor(bg / bgc)

    return utf8.char(codepoint), fg, bg
end

---@class gl.device
---@field init fun(...)
---@field set fun(x: integer, y: integer, c: string, f: integer, b: integer)
---@field sync fun()
---@field size fun(): integer, integer
---@field close fun()

---@param buffer gl.buffer
---@param device gl.device
function gl.flush(buffer, device)
    for chunk in pairs(buffer.dirtyChunks) do
        local cx, cy = gl.computeChunkSlot(buffer, chunk)

        local char, fg, bg = gl.computeChunkValue(buffer, cx, cy)
        device.set(cx, cy, char, fg, bg)
    end
    buffer.dirtyChunks = {}
    device.sync()
end

---@param device gl.device
function gl.newScreenBuffer(device, color)
    color = color or 0
    local w, h = device.size()
    return gl.newBuffer(w * gl.PIXEL_PER_X, h * gl.PIXEL_PER_Y, color)
end

return gl
