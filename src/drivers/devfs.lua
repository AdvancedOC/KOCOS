--[[

DevFS structure:

/dev/components/<type>/<uuid> - Files to open proxies
/dev/parts/<drive uuid>/<part uuid> - Files to access partitions. Partitions on managed partitions appear as files
/dev/zero
/dev/random
/dev/hex
]]

---@class KOCOS.DevFS
---@field partition KOCOS.Partition
---@field handles {[integer]: table}
local devfs = {}
devfs.__index = devfs

---@param partition KOCOS.Partition
function devfs.create(partition)
    if partition.drive.type ~= "devfs" then return nil end

    return setmetatable({
        partition = partition,
        handles = {},
    }, devfs)
end

function devfs:addProxy(proxy)
    local fd = 0
    while self.handles[fd] do fd = fd + 1 end
    self.handles[fd] = proxy
    return fd
end

function devfs:open(path)
    if path == "zero" then
        return self:addProxy {
            address = "zero",
            type = "devfs:zero",
            slot = -1,
        }
    end
    if path == "random" then
        return self:addProxy {
            address = "random",
            type = "devfs:random",
            slot = -1,
        }
    end
    if path == "hex" then
        return self:addProxy {
            address = "hex",
            type = "devfs:hex",
            slot = -1,
        }
    end
    return nil, "bad path"
end

function devfs:close(fd)
    self.handles[fd] = nil
    return true
end

function devfs:write(fd, data)
    local proxy = assert(self.handles[fd])
    return nil, "bad file descriptor"
end

function devfs:read(fd, limit)
    local proxy = assert(self.handles[fd])
    if proxy.address == "zero" then
        if limit == math.huge then limit = 1024 end
        return string.rep("\0", limit)
    end
    if proxy.address == "random" then
        if limit == math.huge then limit = 1024 end
        local s = ""
        for _=1,limit do
            s = s .. string.char(math.random(0, 255))
        end
        return s
    end
    if proxy.address == "hex" then
        if limit == math.huge then limit = 1024 end
        local s = ""
        local hex = "0123456789ABCDEF"
        for _=1,limit do
            local n = math.random(1, 16)
            s = s .. hex:sub(n, n)
        end
        return s
    end
    return nil, "bad file descriptor"
end

function devfs:seek(fd, whence, off)
    local proxy = assert(self.handles[fd])
    return nil, "bad file descriptor"
end

function devfs:ioctl(fd, action, ...)
    local proxy = assert(self.handles[fd])
    if not component.type(proxy.address) then
        error("bad file descriptor")
    end
    return component.invoke(proxy.address, action, ...)
end

function devfs:type(path)
    if path == "" then return "directory" end
    if path == "zero" then return "file" end
    if path == "random" then return "file" end
    if path == "hex" then return "file" end
    if path == "components" then return "directory" end
    if path == "parts" then return "directory" end
    for addr, type in component.list() do
        if path == "components/" .. type then return "directory" end
        if string.startswith(path, "components/" .. type .. "/") then
            local uuid = string.sub(path, #("components/" .. type .. "/"))
            if component.type(uuid) == type then return "file" end
            return "missing"
        end
        local parts = KOCOS.fs.getPartitions(component.proxy(addr))
        if path == "parts/" .. addr and #parts > 0 then
            return "directory"
        end
        for i=1,#parts do
            if path == "parts/" .. addr .. "/" .. parts[i].uuid then
                return "file"
            end
        end
    end
    return "missing"
end

function devfs:list(path)
    if path == "" then
        return {
            "zero",
            "random",
            "hex",
            "components",
            "parts",
        }
    end
    if path == "components" then
        local types = {}
        for _, type in component.list() do
            types[type] = true
        end
        local arr = {}
        for k in pairs(types) do table.insert(arr, k) end
        return arr
    end
    if path == "parts" then
        local drives = {}
        for addr in component.list() do
            if #KOCOS.fs.getPartitions(component.proxy(addr)) > 0 then
                table.insert(drives, addr)
            end
        end
        return drives
    end
    if string.startswith(path, "parts/") then
        for addr in component.list() do
            local parts = KOCOS.fs.getPartitions(component.proxy(addr))
            if path == "parts/" .. addr then
                local arr = {}
                for i=1,#parts do
                    table.insert(arr, parts[i].uuid)
                end
                return arr
            end
        end
    end
    if string.startswith(path, "components/") then
        for _, type in component.list() do
            if path == "components/" .. type then
                local t = {}
                for addr in component.list(type, true) do
                    table.insert(t, addr)
                end
                return t
            end
        end
    end
    return nil, "missing"
end

function devfs:isReadOnly()
    return true
end

function devfs:size(path)
    -- For drives and filesystems, the capacity is the size
    for addr, type in component.list() do
        if path == "components/" .. type .. "/" .. addr then
            if type == "filesystem" then
                return component.invoke(addr, "spaceTotal")
            end
            if type == "drive" then
                return component.invoke(addr, "getCapacity")
            end
        end
    end
    return 0
end

function devfs:remove(path)
    return false, "unsupported"
end

function devfs:spaceUsed()
    return 0
end

function devfs:spaceTotal()
    return 0
end

function devfs:mkdir()
    return false, "unsupported"
end

function devfs:touch()
    return false, "unsupported"
end

function devfs:getPartition()
    return self.partition
end

function devfs:permissionsOf()
    -- Root-only
    return 0
end

KOCOS.fs.addDriver(devfs)

KOCOS.defer(function()
    KOCOS.log("Mounting DevFS")
    ---@type KOCOS.Partition
    local partition = {
        name = "DevFS",
        drive = {
            type = "devfs",
            address = KOCOS.testing.uuid(),
            slot = -1,
            getLabel = function()
                return "DevFS"
            end,
            setLabel = function()
                return "DevFS"
            end,
        },
        uuid = KOCOS.testing.uuid(),
        startByte = 0,
        byteSize = 0,
        kind = "user",
        readonly = true,
        storedKind = KOCOS.testing.uuid(),
    }
    KOCOS.fs.mount("/dev", partition)
end, 2)
