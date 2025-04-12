-- objdump!!!!!

local kelp = require("lib.libkelp.kelp")

local file = assert(arg[1], "missing file")

local f = assert(io.open(file, "r"))
local data = f:read("a")
f:close()

local obj = kelp.parse(data)

for module, code in pairs(obj.modules) do
    local src = obj.sourceMaps[module]
    if src then
        print(string.format("%s (%d bytes) - %s", module, #code, src))
    else
        print(string.format("%s (%d bytes)", module, #code))
    end
    print(code)
end
