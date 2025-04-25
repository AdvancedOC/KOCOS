print("Opening VM...")
local sys = require("syscalls")
local vm = sys.kvmopen("OpenOS")

print("Passing through GPU...")
assert(sys.ioctl(vm, "pass", component.gpu.address))

print("Passing through screen...")
assert(sys.ioctl(vm, "pass", component.screen.address))

print("Passing through keyboard...")
-- Give it its actual address
assert(sys.ioctl(vm, "pass", component.keyboard.address))

print("Passing through EEPROM...")
local code = component.eeprom.get()
assert(sys.ioctl(vm, "addBIOS", code, "", component.eeprom.getLabel()))

print("Passing through keyboard events...")
assert(sys.ioctl(vm, "listen", "key_down", "key_up"))

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
        assert(sys.ioctl(vm, "pass", mount.address))
    end
end

while true do
    if sys.ioctl(vm, "mode") == "halted" then
        -- Clear TTY
        io.write("\x1b[2J")
        io.flush()
        print("Machine halted.")
        os.exit(0)
    end
    local ok, err = sys.ioctl(vm, "resume")
    if not ok then
        local trace = sys.ioctl(vm, "traceback", err)
        print(trace)
        os.exit(1)
    end
    coroutine.yield()
end
