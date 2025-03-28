local outPath

local linked = {}
local moduleMap = {}

do
    local i = 1
    local nextModule
    while i <= #arg do
        if arg[i] == "-o" then
            outPath = assert(arg[i+1], "no output path given")
            i = i + 2
        elseif arg[i] == "-m" then
            nextModule = assert(arg[i+1], "no module given")
            i = i + 2
        elseif arg[i]:sub(1, 2) == "-l" then
            -- Only links in system libraries lol
            local lib = arg[i]:sub(3)
            table.insert(linked, lib)
            i = i + 1
        else
            local path = arg[i]
            assert(path:sub(-4) == ".lua", "Compiler can only be given Lua files")
            local mod = nextModule or path:sub(1, -5):gsub("%/", ".")
            local f = assert(io.open(path, "r"))
            local data = f:read("a")
            f:close()
            moduleMap[mod] = data
            nextModule = nil
            i = i + 1
        end
    end
end

outPath = outPath or "out.o"

local out = assert(io.open(outPath, "w"))
out:setvbuf("no")

-- O for objects, L for shared objects, E for executables
out:write("KELPv1\nO\n")

local dataSegment = ""

do
    out:write("$modules\n")
    local len = 1
    for key, data in pairs(moduleMap) do
        out:write(key, "=", tostring(len), " ", tostring(#data), "\n")
        len = len + #data
        dataSegment = dataSegment .. data
    end
end

if #linked > 0 then
    out:write("$lib\n")
    for _, lib in ipairs(linked) do
        out:write(lib, "\n")
    end
end

out:write("$data\n", dataSegment, "\n")
out:close()
