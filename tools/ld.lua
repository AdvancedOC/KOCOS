-- Silly little linker

local kelp = require("lib.libkelp.kelp")

local out = kelp.empty("E")

local outFile

do
    local i = 1
    while arg[i] do
        local a = arg[i]
        if a == "-o" then
            outFile = assert(arg[i+1], "missing out file")
            i = i + 2
        elseif a:sub(1, 2) == "-l" then
            local lib = a:sub(3)
            kelp.addDependency(out, lib)
            i = i + 1
        else
            local f = assert(io.open(a, "r"))
            local data = f:read("a")
            f:close()

            local obj = kelp.parse(data)

            for module, moddata in pairs(obj.modules) do
                assert(not out.modules[module], "duplicate module: " .. module)
                kelp.setModule(out, module, moddata)
                if obj.sourceMaps[module] then
                    out.sourceMaps[module] = obj.sourceMaps[module]
                end
            end

            for _, lib in ipairs(obj.dependencies) do
                -- Duplicate dependencies are fine and expected
                kelp.addDependency(out, lib)
            end
            i = i + 1
        end
    end
end

outFile = outFile or "out.o"

if outFile:sub(-2) == ".o" then
    out.type = "O"
elseif outFile:sub(-3) == ".so" then
    out.type = "L"
end

local f = assert(io.open(outFile, "w"))

f:write(kelp.encode(out))

f:close()
