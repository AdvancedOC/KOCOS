-- Hand-rolled LZ77-ahh implementation

local input = io.stdin:read("a")

-- They're both 1 over but fuck u
local distanceMax = 2^16-1
local lenMax = 2^8-1

local compressed = ""

-- output the dlc
local function output(d, l, c)
    compressed = compressed .. string.char(d % 256, math.floor(d / 256), l, c)
end

local function match(i)
    local d, l = 0, 0
    for b=1,math.min(i, distanceMax) do
        local len = 0
        while input:sub(i, i+len) == input:sub(i-b, i-b+len) and len < lenMax and i+len < #input do
            len = len + 1
        end
        if len > l and len > 2 then
            l = len
            d = b
        end
    end
    return d, l
end

if true then
    local i = 1
    while i <= #input do
        local d, l = match(i)
        local c = input:byte(i+l, i+l)
        if l == 0 then d = 0 end
        output(d, l, c)
        i = i + l + 1
    end
else
    output(0, 0, string.byte('A'))
    output(0, 0, string.byte('B'))
    output(0, 0, string.byte('C'))
    output(3, 3, string.byte('D'))
    output(0, 0, string.byte('E'))
    output(2, 6, string.byte('F'))
end

--compressed = compressed:gsub(".", {["\r"] = "\\r", ["\n"] = "\\n", ["\\"] = "\\\\", ["'"] = "\\'", ["\""]="\\\""})
local stringStuff = ""
do
    local rep = 0
    while string.find(compressed, "]" .. string.rep("=", rep) .. "]", nil, true) do rep = rep + 1 end
    local srep = string.rep("=", rep)
    --stringStuff = "[" .. srep .. "[" .. compressed .. "]" .. srep .. "]"
    stringStuff = string.format("%q", compressed)
end

--assert(assert(load("return" .. stringStuff))() == compressed) -- sanity check

local out = string.format("local s=%s\n", stringStuff)
out = out .. [[
local decomp = ""
local function write(c)
    decomp = decomp .. c
end
local function dlc(i)
    local a, b, c, d = s:byte(i*4-3, i*4)
    return a + b * 256, c, d
end

for i=1,#s/4 do
    local d, l, c = dlc(i)
    for j=1,l do
        write(decomp:sub(-d, -d))
    end
    write(string.char(c))
end
return assert(load(decomp, "=decompressed"))(...)
]]
assert(load(out, "=output"))()
