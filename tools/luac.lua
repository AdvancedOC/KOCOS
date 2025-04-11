local kelp = require("lib.libkelp.kelp")

local outPath

local obj = kelp.empty("O")

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
            kelp.addDependency(obj, lib)
            i = i + 1
        else
            local path = arg[i]
            assert(path:sub(-4) == ".lua", "Compiler can only be given Lua files")
            local mod = nextModule or path:sub(1, -5):gsub("%/", ".")
            local f = assert(io.open(path, "r"))
            local data = f:read("a")
            f:close()
            kelp.setModule(obj, mod, data)
            kelp.mapSource(obj, mod, path)
            nextModule = nil
            i = i + 1
        end
    end
end

outPath = outPath or "out.o"

local out = assert(io.open(outPath, "w"))
out:setvbuf("no")

out:write(kelp.encode(obj))

out:close()
