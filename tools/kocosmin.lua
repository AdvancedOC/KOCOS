assert(io.exists, "Run on KOCOS!!!!!")

local data = assert(component.data, "missing data card. We can't fit libdeflate on this garbage")

local kernelFile = assert(io.open("/kernel.lua"))
print("Reading kernel...")
local kernel = kernelFile:read("a")
kernelFile:close()

printf("Kernel read (%s)", string.memformat(#kernel))

local deflated = assert(data.deflate(kernel))

printf("Kernel deflated to (%s)", string.memformat(#deflated))

printf("Generating self-decompressing binary...")

local runtime = [[
local s = %q;
local data = component.list("data")()
assert(data, "missing data card")
local inflated = assert(component.invoke(data, "inflate", s))
return assert(load(inflated, "=kocos"))(...)
]]

local s = string.format(runtime, deflated)

printf("Self-decompressing binary generated (%s)", string.memformat(#s))

local output = arg[1] or "/kernel.lua"

printf("Writing to %s", output)

local out = assert(io.open(output, "w"))
assert(out:write(s))
out:close()

print("Done. Enjoy!")
