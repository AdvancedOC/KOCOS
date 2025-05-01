--[[

DevFS structure:

/dev/components/<type>/<uuid> - Files to open proxies
/dev/parts/<part uuid> - Files to access partitions. Partitions on managed partitions appear as files
/dev/drives/<drive uuid> - Files to access whole drives.
/dev/null
/dev/zero
/dev/random
/dev/hex
/dev/eeprom
/dev/eeprom-data
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

function devfs.format()
    return false
end

---@param uuid string
local function formatUUID(uuid)
    return uuid:sub(1, 8)
end

function devfs:addProxy(proxy)
    local fd = #self.handles
    while self.handles[fd] do fd = fd + 1 end
    self.handles[fd] = proxy
    return fd
end

function devfs:open(path, mode)
    if mode == "i" then return nil, "bad mode" end -- it just simply doesn't work
    if path == "zero" then
        return self:addProxy {
            address = "zero",
            type = "devfs:zero",
        }
    end
    if path == "null" then
        return self:addProxy {
            address = "null",
            type = "devfs:null",
        }
    end
    if path == "random" then
        return self:addProxy {
            address = "random",
            type = "devfs:random",
        }
    end
    if path == "hex" then
        return self:addProxy {
            address = "hex",
            type = "devfs:hex",
        }
    end
    if path == "eeprom" then
        local eeprom = component.eeprom
        if mode == "w" then
            eeprom.set("") -- unbelievably unsafe
        end
        return self:addProxy {
            address = eeprom.address,
            type = "devfs:eeprom",
            current = 0,
            eeprom = eeprom,
        }
    end
    if path == "eeprom-data" then
        local eeprom = component.eeprom
        if mode == "w" then
            eeprom.setData("") -- unbelievably unsafe
        end
        return self:addProxy {
            address = eeprom.address,
            type = "devfs:eeprom-data",
            current = 0,
            eeprom = eeprom,
        }
    end
    if mode == "a" then return nil, "bad mode" end -- it just simply doesn't work on drives and partitions
    for addr, drive in KOCOS.vdrive.list() do
        if path == "drives/" .. formatUUID(addr) then
            local proxy = drive -- we plan to mutate
            proxy.current = 0
            proxy.mode = mode
            return self:addProxy(proxy)
        end
    end
    local allParts = KOCOS.fs.findAllPartitions{}
    for _, part in ipairs(allParts) do
        if path == "parts/" .. formatUUID(part.uuid) then
            return self:addProxy{
                type = "partition",
                slot = part.drive.slot,
                partition = part,
                current = 0,
                mode = mode,
            }
        end
    end
    return nil, "bad path"
end

function devfs:close(fd)
    self.handles[fd] = nil
    return true
end

-- In case in the future we want to support partitions with different kinds of backing storage

local function writeBuffer(addr, off, data)
    local proxy = KOCOS.vdrive.proxy(addr) or component.proxy(addr)
    if not proxy then return false, "bad file descriptor" end

    if proxy.type == "drive" then
        local capacity = proxy.getCapacity()
        if off + #data > capacity then return false, "out of space" end
        local sectorSize = proxy.getSectorSize()
        while #data > 0 do
            if (#data >= sectorSize) and ((off / sectorSize) == math.floor(off / sectorSize)) then
                local sector = math.floor(off / sectorSize)
                proxy.writeSector(sector+1, data:sub(1, sectorSize))
                data = data:sub(sectorSize+1)
                off = off + sectorSize
            else
                local b = data:byte()
                if b >= 128 then
                    b = b - 256
                end
                proxy.writeByte(off+1, b)
                off = off + 1
                data = data:sub(2)
            end
        end
        return true
    end
    return false, "bad file descriptor"
end

local function readBuffer(addr, off, limit)
    local proxy = KOCOS.vdrive.proxy(addr) or component.proxy(addr)
    if not proxy then return nil end
    local s = ""

    if proxy.type == "drive" then
        local capacity = proxy.getCapacity()
        local left = math.min(limit, capacity-off)
        local sectorSize = proxy.getSectorSize()
        while left > 0 do
            if (left >= sectorSize) and ((off / sectorSize) == math.floor(off / sectorSize)) then
                local sector = math.floor(off / sectorSize)
                local data = assert(proxy.readSector(sector+1))
                s = s .. data
                off = off + sectorSize
                left = left - sectorSize
            else
                local b, err = proxy.readByte(off+1)
                assert(b, err)
                if b < 0 then b = b + 256 end
                s = s .. string.char(b)
                off = off + 1
                left = left - 1
            end
        end
    elseif proxy.type == "eeprom" then
        local data = proxy.get()
        if not data then return end -- EEPROM probably removed
        if limit == math.huge then limit = #data end
        local chunk = data:sub(off+1, off+limit)
        if #chunk == 0 then return end
        return chunk
    end

    if #s == 0 then return nil end

    return s
end

function devfs:write(fd, data)
    local proxy = assert(self.handles[fd], "bad file descriptor")
    if proxy.type == "devfs:eeprom" then
        local eeprom = proxy.eeprom
        local src = eeprom.get()
        if not src then return end -- EEPROM probably removed
        src = src:sub(1, proxy.current) .. data .. src:sub(proxy.current+1)
        if #src > eeprom.getSize() then return false, "out of space" end
        eeprom.set(src)
        proxy.current = proxy.current + #data
        return true
    end
    if proxy.type == "devfs:eeprom-data" then
        local eeprom = proxy.eeprom
        local src = eeprom.getData()
        if not src then return end -- EEPROM probably removed
        src = src:sub(1, proxy.current) .. data .. src:sub(proxy.current+1)
        if #src > eeprom.getDataSize() then return false, "out of space" end
        eeprom.setData(src)
        proxy.current = proxy.current + #data
        return true
    end
    if proxy.type == "drive" then
        return writeBuffer(proxy.address, proxy.current, data)
    end
    if proxy.type == "partition" then
        return writeBuffer(proxy.partition.drive.address, proxy.partition.startByte + proxy.current, data)
    end
    return nil, "bad file descriptor"
end

function devfs:read(fd, limit)
    local proxy = assert(self.handles[fd], "bad file descriptor")
    if proxy.address == "null" then
        return nil
    end
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
    if proxy.type == "devfs:eeprom" then
        local eeprom = proxy.eeprom
        local data = eeprom.get()
        if not data then return end -- EEPROM probably removed
        -- Yes, eeprom contents is not as big as the file...
        if limit == math.huge then limit = #data end
        local chunk = data:sub(proxy.current+1, proxy.current+limit)
        proxy.current = proxy.current + #chunk
        if #chunk == 0 then return end
        return chunk
    end
    if proxy.type == "devfs:eeprom-data" then
        local eeprom = proxy.eeprom
        local data = eeprom.getData()
        if not data then return end -- EEPROM probably removed
        -- Yes, eeprom contents is not as big as the file...
        if limit == math.huge then limit = #data end
        local chunk = data:sub(proxy.current+1, proxy.current+limit)
        proxy.current = proxy.current + #chunk
        if #chunk == 0 then return end
        return chunk
    end
    if proxy.type == "drive" then
        local data = readBuffer(proxy.address, proxy.current, limit)
        if data then proxy.current = proxy.current + #data end
        return data
    end
    if proxy.type == "partition" then
        local data = readBuffer(proxy.partition.drive.address, proxy.partition.startByte + proxy.current, limit)
        if data then proxy.current = proxy.current + #data end
        return data
    end
    return nil, "bad file descriptor"
end

function devfs:seek(fd, whence, off)
    local proxy = assert(self.handles[fd], "bad file descriptor")
    if proxy.type == "drive" or proxy.type == "partition" or proxy.type == "devfs:eeprom" or proxy.type == "devfs:eeprom-data" then
        local size = 0
        if proxy.type == "drive" then
            size = proxy.getCapacity()
        end
        if proxy.type == "partition" then
            size = proxy.paritition.byteSize
        end
        local cur = proxy.current
        if whence == "set" then
            cur = off
        elseif whence == "cur" then
            cur = cur + off
        else
            cur = size - off
        end
        proxy.current = math.clamp(cur, 0, size)
        return proxy.current
    end
    return nil, "bad file descriptor"
end

function devfs:ioctl(fd, action, ...)
    local proxy = assert(self.handles[fd])
    if action == "type" then
        return proxy.type
    elseif action == "slot" then
        return proxy.slot or -1
    elseif action == "address" then
        return proxy.address
    elseif action == "part:offset" and proxy.type == "partition" then
        return proxy.partition.startByte
    elseif action == "part:kind" and proxy.type == "partition" then
        return proxy.partition.kind
    elseif action == "part:storedKind" and proxy.type == "partition" then
        return proxy.partition.storedKind
    elseif action == "isReadOnly" and proxy.type == "partition" then
        return proxy.partition.readonly
    elseif action == "getLabel" and proxy.type == "partition" then
        return proxy.partition.name
    elseif action == "getCapacity" and proxy.type == "partition" then
        return proxy.partition.byteSize
    elseif action == "part:drive" and proxy.type == "partition" then
        return proxy.partition.drive.address
    end
    return component.invoke(proxy.address, action, ...)
end

function devfs:type(path)
    if path == "" then return "directory" end
    if path == "null" then return "file" end
    if path == "zero" then return "file" end
    if path == "random" then return "file" end
    if path == "hex" then return "file" end
    if path == "eeprom" then return "file" end
    if path == "eeprom-data" then return "file" end
    if path == "components" then return "directory" end
    if path == "parts" then return "directory" end
    if path == "drives" then return "directory" end
    for addr, type in component.list() do
        if path == "components/" .. type then return "directory" end
        if string.startswith(path, "components/" .. type .. "/") then
            local uuid = string.sub(path, #("components/" .. type .. "/"))
            if component.type(uuid) == type then return "file" end
            return "missing"
        end
        if path == "drives/" .. formatUUID(addr) and KOCOS.vdrive.proxy(addr) then
            return "file"
        end
    end
    local allParts = KOCOS.fs.findAllPartitions{}
    for _, part in ipairs(allParts) do
        if path == "parts/" .. formatUUID(part.uuid) then
            return "file"
        end
    end
    return "missing"
end

function devfs:list(path)
    if path == "" then
        return {
            "null",
            "zero",
            "random",
            "hex",
            "eeprom",
            "eeprom-data",
            "components",
            "parts",
            "drives",
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
        local allParts = KOCOS.fs.findAllPartitions{}
        local arr = {}
        for i=1,#allParts do
            table.insert(arr, formatUUID(allParts[i].uuid))
        end
        return arr
    end
    if path == "drives" then
        local drives = {}
        for addr in KOCOS.vdrive.list() do
            table.insert(drives, formatUUID(addr))
        end
        return drives
    end
    if string.startswith(path, "components/") then
        for _, type in component.list() do
            if path == "components/" .. type then
                local t = {}
                for addr in component.list(type, true) do
                    table.insert(t, formatUUID(addr))
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
    if path == "eeprom" then
        local eeprom = component.eeprom
        if not eeprom then return 0 end
        return eeprom.getSize()
    end
    if path == "eeprom-data" then
        local eeprom = component.eeprom
        if not eeprom then return 0 end
        return eeprom.getDataSize()
    end
    -- For drives and filesystems, the capacity is the size
    for addr, type in component.list() do
        if path == "components/" .. type .. "/" .. formatUUID(addr) then
            if type == "filesystem" then
                return component.invoke(addr, "spaceTotal")
            end
            if type == "drive" then
                return component.invoke(addr, "getCapacity")
            end
            if type == "eeprom" then
                return component.invoke(addr, "getSize")
            end
        end
        if path == "drives/" .. formatUUID(addr) then
            local p = KOCOS.vdrive.proxy(addr)
            if not p then return 0 end
            return p.getCapacity()
        end
    end
    local allParts = KOCOS.fs.findAllPartitions{}
    for _, part in ipairs(allParts) do
        if path == "parts/" .. formatUUID(part.uuid) then
            return part.byteSize
        end
    end
    return 0
end

function devfs:remove()
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

function devfs:permissionsOf(path)
    local allGood = KOCOS.perms.encode(KOCOS.perms.ID_ALL, KOCOS.perms.BIT_READABLE, KOCOS.perms.ID_ALL, KOCOS.perms.BIT_READABLE)
    local goodToUse = {
        "null",
        "zero",
        "random",
        "hex",
    }
    if allGood then
        for _, good in ipairs(goodToUse) do
            if good == path then
                return allGood
            end
        end
    end
    -- Root-only
    return KOCOS.perms.encode(0, KOCOS.perms.BIT_RW, KOCOS.perms.ID_ALL, 0)
end

function devfs:modifiedTime()
    -- instantly reactive means always modified
    return os.time()
end

function devfs:setPermissionsOf(path, perms)
    error("unsupported")
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

KOCOS.log("DevFS driver loaded")
