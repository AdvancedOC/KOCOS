local bit32Code = [[
bit32 = {}

function bit32.arshift(x, disp)
    return x >> disp
end

function bit32.band(...)
    local t = -1
    local n = select("#", ...)
    for i=1,n do
        local m = select(i, ...)
        t = t & m
    end
    return t
end

function bit32.bnot(x)
    return ~x
end

function bit32.bor(...)
    local t = 0
    local n = select("#", ...)
    for i=1,n do
        local m = select(i, ...)
        t = t | m
    end
    return t
end

function bit32.btest(...)
    return bit32.band(...) ~= 0
end

function bit32.bxor(...)
    local t = 0
    local n = select("#", ...)
    for i=1,n do
        local m = select(i, ...)
        t = t ~ m
    end
    return t
end

-- TODO: rest of bit32
-- See https://www.lua.org/manual/5.2/manual.html#6.7

KOCOS.test("bit32", function()
    assert(bit32.band(5, 3) == 1)
    assert(bit32.bor(5, 3) == 7)
    assert(bit32.bxor(5, 3) == 6)
    assert(bit32.arshift(65536, 16) == 1)
    assert(bit32.arshift(1, -16) == 65536)
end)
]]

if not bit32 then
    load(bit32Code, "=bit32")()
end
