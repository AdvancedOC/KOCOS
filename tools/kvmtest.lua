print("Opening VM...")
---@module 'lib.libkvm.kvm'
local kvm = require("kvm")
---@type libkvm
local vm = assert(kvm.open("KVM Test"))

if component.ocelot then
    print("Passing through ocelot component...")
    vm:pass(component.ocelot.address)
end

print("Select environment type")
print("1. GPU hardware")
print("2. KOCOS TTY sharing")
local opt = io.read("l")

if opt == "1" then
    print("Passing through GPU...")
    vm:pass(component.gpu.address)

    print("Passing through screen...")
    vm:pass(component.screen.address)

    print("Passing through keyboard...")
    -- Give it its actual address
    vm:pass(component.keyboard.address)

    print("Passing through EEPROM...")
    local code = component.eeprom.get()
    vm:addBIOS(code, "", component.eeprom.getLabel())

    print("Passing through keyboard events...")
    vm:listen("key_down", "key_up", "clipboard")
elseif opt == "2" then
    print("Adding custom BIOS")
local kocosBios = [[
local function loadOS(addr)
    local p = component.proxy(addr)
    if p.type == "filesystem" then
        if not p.exists("/init.lua") then return end
        local f = p.open("/init.lua", "r")
        local data = ""
        while true do
            local chunk = p.read(f, math.huge)
            if not chunk then break end
            data = data .. chunk
        end
        p.close(f)
        return load(data, "=/init.lua")
    end
end

local f

for addr in component.list() do
    f = loadOS(addr)
    if f then
        computer.getBootAddress = function()
            return addr
        end
        computer.setBootAddress = function() end
        break
    end
end

f()
]]
    vm:addBIOS(kocosBios, "", "KOCOS BIOS")

    print("Adding KOCOS component...")
    vm:addKocos {
        componentFetch = component.list,
        validateMount = function(path)
            printf("Allow mounting of %s? [y/N]", path)
            local l = io.read("l")
            if not l then return false, "nah" end
            return l:lower():sub(1, 1) == "y"
        end,
        validatePassthrough = function(address)
            if not component.type(address) then return false, "missing" end
            printf("Allow mounting of %s (%s)? [y/N]", address, component.type(address))
            local l = io.read("l")
            if not l then return false, "nah" end
            return l:lower():sub(1, 1) == "y"
        end,
    }
else
    error("bad option bruh")
end

local mounts = {}
for addr in component.list("filesystem") do
    local p = component.proxy(addr)
    table.insert(mounts, p)
end

local enabled = {}

while true do
    print("Toggle drives to pass through")
    print("Type nothing once done")
    for i, mount in ipairs(mounts) do
        local name = mount.getLabel() or mount.address:sub(1, 8)
        printf("%d. %s [%s]", i, name, enabled[mount.address] and "Y" or "N")
    end
    local l = io.read("l")
    local s = tonumber(l)
    if s then
        local m = mounts[s]
        if m then
            enabled[m.address] = true
        end
    end
    if l == "" then
        break
    end
end

for _, mount in ipairs(mounts) do
    if enabled[mount.address] then
        printf("Passing through %s...", mount.address)
        vm:pass(mount.address)
    end
end

while true do
    print("Extra paths to mount")
    print("Empty to exit")
    local line = io.read("l")
    if not line or line == "" then break end

    if io.ftype(line) == "directory" then
        print("Mounting " .. line .. " as filesystem...")
        vm:addFilesystem(line, line)
    else
        print("Bad path")
    end
end

while true do
    if vm:mode() == "halted" then
        if opt ~= "2" then
            -- Clear TTY
            io.write("\x1b[2J")
            io.flush()
        end
        print("Machine halted.")
        os.exit(0)
    end
    local ok, err = vm:resume()
    if not ok then
        local trace = vm:traceback(err)
        print(trace)
        os.exit(1)
    end
    coroutine.yield()
end
