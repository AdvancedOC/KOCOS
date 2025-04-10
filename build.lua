local sources = {
    -- First cuz it needs to make everything exist
    "src/prelude.lua",
    -- All the other shit
    "src/utils.lua",
    "src/testing.lua",
    "src/bit32.lua",
    "src/event.lua",
    "src/component.lua",
    "src/fs.lua",
    "src/process.lua",
    "src/network.lua",
    "src/syscalls.lua",
    "src/tty.lua",
    "src/auth.lua",
    "src/router.lua",
    "src/drivers/procfs.lua",
    "src/drivers/devfs.lua",
    "src/drivers/managedfs.lua",
    "src/drivers/gpt.lua",
    "src/drivers/okffs.lua",
    "src/drivers/internet.lua",
    -- Needs to be last cuz self-boots.
    "src/postlude.lua",
}

local out = arg[1] or "kernel.lua"
local isBinary = out:sub(-4) ~= ".lua"
local code = ""

for _, source in ipairs(sources) do
    local file = io.open(source:gsub("%/", package.config:sub(1, 1)), "r")
    if file then
        local src = file:read("*all")
        code = code .. "do\n" .. src .. "\nend\n"
        io.close(file)
    else
        print("WARNING: Missing file " .. source .. " but continuing anyways (assuming removed feature)")
    end
end

local f = assert(io.open(out, "wb"))
if isBinary then
    local codeFunc = assert(load(code, "=kernel"))
    f:write(string.dump(codeFunc))
else
    f:write(code)
end
