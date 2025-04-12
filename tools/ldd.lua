-- Silly linker debugger

local kelp = require("lib.libkelp.kelp")

local file = assert(arg[1], "missing input")

local f = assert(io.open(file, "r"))
local data = f:read("a")
f:close()

local obj = kelp.parse(data)

local kinds = {
    O = "object",
    E = "executable",
    L = "shared object",
}

print(file .. ": " .. kinds[obj.type])
for _, dep in ipairs(obj.dependencies) do
    print(dep)
end
if #obj.dependencies == 0 then
    print("statically linked")
end
