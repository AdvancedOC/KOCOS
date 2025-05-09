local sources = {
    -- First cuz it needs to make everything exist
    "src/prelude.lua",
    -- All the other shit
    "src/utils.lua",
    "src/lock.lua",
    "src/tty.lua",
    "src/event.lua",
    "src/testing.lua",
    "src/bit32.lua",
    "src/component.lua",
    "src/fs.lua",
    "src/process.lua",
    "src/objects.lua",
    "src/network.lua",
    "src/syscalls.lua",
    "src/keyboard.lua",
    "src/auth.lua",
    "src/radio.lua",
    "src/router.lua",
    "src/kvm.lua",
    "src/drivers/procfs.lua",
    "src/drivers/devfs.lua",
    "src/drivers/managedfs.lua",
    "src/drivers/gpt.lua",
    "src/drivers/mtpt.lua",
    "src/drivers/osdi.lua",
    "src/drivers/kpr.lua",
    "src/drivers/okffs.lua",
    "src/drivers/lightfs.lua",
    "src/drivers/tape_drive.lua",
    "src/drivers/internet.lua",
    "src/drivers/domain.lua",
    "src/drivers/radio_sockets.lua",
    "src/drivers/ktar.lua",
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
        file:close()
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
