local managedfs = {}
managedfs.__index = managedfs

---@param partition KOCOS.Partition
function managedfs.create(partition)
    if partition.drive.type ~= "filesystem" then return nil end

    return setmetatable({
        partition = partition,
        disk = partition.drive,
        permsMap = {},
    }, managedfs)
end

function managedfs.format()
    return false
end

function managedfs:open(path, mode)
    local fd, err = self.disk.open(path, mode)
    if err then return nil, err end
    return fd
end

function managedfs:close(fd)
    return self.disk.close(fd)
end

function managedfs:read(fd, len)
    return self.disk.read(fd, len)
end

function managedfs:write(fd, data)
    return self.disk.write(fd, data)
end

function managedfs:seek(fd, whence, offset)
    return self.disk.seek(fd, whence, offset)
end

function managedfs:type(path)
    if self.disk.isDirectory(path) then
        return "directory"
    elseif self.disk.exists(path) then
        return "file"
    else
        return "missing"
    end
end

function managedfs:list(path)
    return self.disk.list(path)
end

function managedfs:isReadOnly(_)
    return self.disk.isReadOnly()
end

function managedfs:size(path)
    return self.disk.size(path)
end

function managedfs:remove(path)
    self.permsMap[path] = nil
    return self.disk.remove(path)
end

function managedfs:spaceUsed()
    return self.disk.spaceUsed()
end

function managedfs:spaceTotal()
    return self.disk.spaceTotal()
end

function managedfs:mkdir(path)
    return self.disk.makeDirectory(path)
end

function managedfs:touch(path)
    if self.disk.exists(path) then return end
    local f, err = self.disk.open(path, "w")
    if err then return nil, err end
    self.disk.close(f)
    return true
end

function managedfs:permissionsOf(path)
    if self.permsMap[path] then return self.permsMap[path] end
    if self.disk.isReadOnly() then
        local perms = KOCOS.perms
        return perms.encode(perms.ID_ALL, perms.BIT_READABLE, perms.ID_ALL, perms.BIT_READABLE)
    end
    return 2^16-1 -- Don't ask
end

function managedfs:setPermissionsOf(path, perms)
    if not self.disk.exists(path) then
        error("bad path")
    end
    self.permsMap[path] = perms
end

---@param path string
function managedfs:modifiedTime(path)
    return self.disk.lastModified(path) / 1000
end

function managedfs:ioctl(fd, action, ...)
    if action == "disk" then
        return self.disk.address
    end

    error("unsupported")
end

function managedfs:getPartition()
    return self.partition
end

KOCOS.fs.addDriver(managedfs)

KOCOS.fs.addPartitionParser(function(parser)
    if parser.type == "filesystem" then
        ---@type KOCOS.Partition[]
        local parts = {
            {
                startByte = 0,
                byteSize = parser.spaceTotal(),
                kind = "root",
                name = parser.getLabel() or parser.address:sub(1, 6),
                uuid = parser.address,
                storedKind = "root",
                readonly = parser.isReadOnly(),
                drive = parser,
            },
        }

        return parts, "managed"
    end
end)

KOCOS.log("ManagedFS driver loaded")
