-- TODO: support symlinks

---@alias KOCOS.FileSystemDriver table

---@class KOCOS.File
---@field mode "w"|"r"|"a"|"i"
---@field refc integer
---@field kind "disk"|"memory"|"pipe"|"stream"
---@field events KOCOS.EventSystem

---@class KOCOS.DiskFile: KOCOS.File
---@field kind "disk"
---@field fd any
---@field manager KOCOS.FileSystemDriver

---@class KOCOS.MemoryFile: KOCOS.File
---@field kind "memory"
---@field buffer? string
---@field bufcap integer
---@field cursor integer

---@class KOCOS.PipeFile: KOCOS.File
---@field kind "pipe"
---@field output KOCOS.File
---@field input KOCOS.File

---@class KOCOS.StreamFile: KOCOS.File
---@field kind "stream"
---@field writer fun(data: string): boolean, string
---@field reader fun(limit: integer): string?, string?
---@field seek fun(whence: seekwhence, off: integer): integer?, string
---@field close fun(): boolean, string
---@field ioctl fun(...): ...

local fs = {}

fs.drivers = {}

---@type {[string]: KOCOS.FileSystemDriver}
local globalTranslation = {}

---@param path string
function fs.canonical(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")
    local stack = {}

    for _, part in ipairs(parts) do
        if #part > 0 then
            table.insert(stack, part)
            if part == string.rep(".", #part) then
                for _=1,#part do
                    stack[#stack] = nil
                end
            end
        end
    end

    return "/" .. table.concat(stack, "/")
end

function fs.join(...)
    return fs.canonical(table.concat({...}, "/"))
end

---@return KOCOS.FileSystemDriver, string
function fs.resolve(path)
    path = fs.canonical(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")

    for i=#parts, 1, -1 do
        local subpath = table.concat(parts, "/", 1, i)
        local manager = globalTranslation[subpath]
        if type(manager) == "table" then
            return manager, table.concat(parts, "/", i+1)
        end
    end

    return globalTranslation[""], path
end

---@param mode "w"|"r"|"a"
---@param content? string
---@param maximum? integer
---@return KOCOS.MemoryFile
function fs.mopen(mode, content, maximum)
    content = content or ""
    maximum = maximum or math.huge
    if #content > maximum then content = content:sub(1, maximum) end
    ---@type KOCOS.MemoryFile
    return {
        mode = mode,
        kind = "memory",
        refc = 1,
        events = KOCOS.event.create(KOCOS.maxEventBacklog),
        -- Memory shit
        buffer = content,
        bufcap = maximum,
        cursor = 0,
    }
end

---@param input KOCOS.File
---@param output KOCOS.File
---@return KOCOS.PipeFile
function fs.mkpipe(input, output)
    ---@type KOCOS.PipeFile
    local pipe = {
        mode = "w",
        kind = "pipe",
        refc = 1,
        events = KOCOS.event.create(KOCOS.maxEventBacklog),
        input = input,
        output = output,
    }

    fs.retain(input)
    fs.retain(output)
    return pipe
end

---@param opts table
---@return KOCOS.StreamFile
function fs.mkstream(opts)
    ---@type KOCOS.StreamFile
    return {
        mode = "w",
        kind = "stream",
        refc = 1,
        events = KOCOS.event.create(KOCOS.maxEventBacklog),
        writer = opts.write or function() return false, "unsupported" end,
        reader = opts.read or function() end,
        close = opts.close or function() end,
        seek = opts.seek or function() return nil, "unsupported" end,
        ioctl = opts.ioctl or function() error("unsupported") end
    }
end

---@param path string
---@param mode "w"|"r"|"a"|"i"
---@return KOCOS.DiskFile?, string
function fs.open(path, mode)
    if fs.type(path) == "missing" then return nil, "missing file" end
    -- Pre-alloc file to OOM early
    ---@type KOCOS.DiskFile
    local file = {
        mode = mode,
        kind = "disk",
        refc = 1,
        events = KOCOS.event.create(KOCOS.maxEventBacklog),
        fd = 0, -- we set to 0 and not nil so .fd = fd doesn't OOM us
        manager = fs,
    }

    local manager, truepath = fs.resolve(path)
    file.manager = manager
    local fd, err = manager:open(truepath, mode)
    if err then return nil, err end
    file.fd = fd
    return file, ""
end


---@param file KOCOS.File
---@param n? integer
function fs.retain(file, n)
    n = n or 1
    file.refc = file.refc + n
end

---@alias KOCOS.FileType "file"|"directory"|"missing"

---@param path string
---@return KOCOS.FileType
function fs.type(path)
    local manager, realpath = fs.resolve(path)

    return manager:type(realpath)
end

---@param path string
---@return boolean
function fs.readonly(path)
    local manager, realpath = fs.resolve(path)

    return manager:isReadOnly(realpath)
end

---@param path string
---@return string[]?, string
function fs.list(path)
    local manager, realpath = fs.resolve(path)

    return manager:list(realpath)
end

---@param path string
function fs.exists(path)
    return fs.type(path) ~= "missing"
end

---@param file KOCOS.File
---@return boolean, string
function fs.close(file)
    file.refc = file.refc - 1
    if file.refc > 0 then return true, "" end

    file.events.clear()

    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        file.manager:close(file.fd)
    elseif file.kind == "pipe" then
        ---@cast file KOCOS.PipeFile
        pcall(fs.close, file.input)
        pcall(fs.close, file.output)
    elseif file.kind == "stream" then
        ---@cast file KOCOS.StreamFile
        return file.close()
    end
    return true, ""
end

---@param file KOCOS.File
---@param data string
---@return boolean, string
function fs.write(file, data)
    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:write(file.fd, data)
    elseif file.kind == "memory" then
        if file.buffer == nil then return false, "closed" end
        ---@cast file KOCOS.MemoryFile
        if file.mode == "w" then
            if (#file.buffer + #data) > file.bufcap then
                return false, "out of space"
            end
            file.buffer = file.buffer .. data
            return true, ""
        end

        if #file.buffer + #data > file.bufcap then return false, "out of space" end

        local before = file.buffer:sub(1, file.cursor)
        local after = file.buffer:sub(file.cursor+1)
        file.buffer = before .. data .. after
        file.cursor = file.cursor + #data
    elseif file.kind == "pipe" then
        ---@cast file KOCOS.PipeFile
        return fs.write(file.output, data)
    elseif file.kind == "stream" then
        ---@cast file KOCOS.StreamFile
        return file.writer(data)
    end
    return false, "bad file"
end

---@param file KOCOS.File
---@param len integer
---@return string?, string?
function fs.read(file, len)
    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:read(file.fd, len)
    elseif file.kind == "memory" then
        if file.buffer == nil then return end
        ---@cast file KOCOS.MemoryFile
        if file.mode == "w" then
            if #file.buffer == 0 then
                pcall(file.events.push, "starved", len)
            end
            local l = len
            -- Negative lengths indicate some goofy ahh TTY shit
            if l < 0 then l = math.huge end
            if l < #file.buffer then
                local chunk = file.buffer:sub(1, l)
                file.buffer = file.buffer:sub(l+1)
                return chunk, nil
            end
            local data = file.buffer or ""
            file.buffer = ""
            return data, nil
        end

        local data = file.buffer:sub(file.cursor+1, (len ~= math.huge) and file.cursor+len or nil)
        if #data == 0 then
            if file.mode == "w" then
                -- w means this is used as an endless stream
                return "", nil
            end
            return nil, nil
        end
        file.cursor = file.cursor + #data
        if file.cursor > #file.buffer then
            file.cursor = #file.buffer
        end
        return data, nil
    elseif file.kind == "pipe" then
        ---@cast file KOCOS.PipeFile
        return fs.read(file.input, len)
    elseif file.kind == "stream" then
        ---@cast file KOCOS.StreamFile
        return file.reader(len)
    end
    return nil, "bad file"
end

---@param file KOCOS.File
---@param whence "set"|"cur"|"end"
---@param offset integer
---@return integer?, string
function fs.seek(file, whence, offset)
    if file.kind == "memory" then
        ---@cast file KOCOS.MemoryFile
        if file.mode == "w" then
            return nil, "unable to seek stream"
        end
        if whence == "set" then
            file.cursor = offset
        elseif whence == "cur" then
            file.cursor = file.cursor + offset
        elseif whence == "end" then
            file.cursor = #file.buffer - offset
        end
        if file.cursor < 0 then file.cursor = 0 end
        if file.cursor > #file.buffer then file.cursor = #file.buffer end
        return file.cursor, ""
    elseif file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:seek(file.fd, whence, offset)
    elseif file.kind == "stream" then
        ---@cast file KOCOS.StreamFile
        return file.seek(whence, offset)
    end

    -- TODO: implement
    return nil, "bad file"
end

---@param file KOCOS.File
---@param action string
---@return ...
function fs.ioctl(file, action, ...)
    if file.kind == "memory" then
        ---@cast file KOCOS.MemoryFile
        if action == "clear" then
            file.buffer = ""
            file.cursor = 0
            file.events.clear()
            return true
        end
        if action == "fetch" then
            return file.buffer
        end
        if action == "close" then
            -- If pipes wish to support binary mode,
            -- You can't close them via End of Transmission,
            -- thus you *have* to mark the memory file as closed.
            file.buffer = nil
            return
        end
    elseif file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:ioctl(file.fd, action, ...)
    elseif file.kind == "stream" then
        ---@cast file KOCOS.StreamFile
        return file.ioctl(...)
    end

    error("bad file")
end

---@param path string
---@return integer
function fs.spaceUsed(path)
    local manager = fs.resolve(path)
    return manager:spaceUsed()
end

---@param path string
---@return integer
function fs.spaceTotal(path)
    local manager = fs.resolve(path)
    return manager:spaceTotal()
end

---@param path string
---@return integer
function fs.size(path)
    local manager, truePath = fs.resolve(path)
    return manager:size(truePath)
end

---@param path string
function fs.parentOf(path)
    local parts = string.split(fs.canonical(path), "%/")
    parts[#parts] = nil
    return "/" .. table.concat(parts, "/")
end

---@return KOCOS.Partition
function fs.partitionOf(path)
    local manager = fs.resolve(path)
    return manager:getPartition()
end

---@class KOCOS.Partition
---@field drive table
---@field startByte integer
---@field byteSize integer
---@field name string
---@field uuid string
---@field storedKind string
---@field kind "boot"|"root"|"user"|"reserved"
---@field readonly boolean

---@alias KOCOS.PartitionParser fun(component: table): KOCOS.Partition[]?, string?

---@type KOCOS.PartitionParser[]
fs.partitionParsers = {}

---@param parser KOCOS.PartitionParser
function fs.addPartitionParser(parser)
    table.insert(fs.partitionParsers, parser)
end

---@param drive table
---@return KOCOS.Partition[], string
function fs.getPartitions(drive)
    for i=#fs.partitionParsers,1,-1 do
        local parts, format = fs.partitionParsers[i](drive)
        if parts then
            return parts, format or "unknown"
        end
    end

    -- Can't partition if unknown lol
    return {}, "unsupported"
end

function fs.addDriver(driver)
    table.insert(fs.drivers, driver)
end

---@param partition KOCOS.Partition
---@return KOCOS.FileSystemDriver?
function fs.driverFor(partition)
    for i=#fs.drivers,1,-1 do
        local driver = fs.drivers[i]
        local manager = driver.create(partition)
        if manager then return manager end
    end
end

---@param path string
---@param partition KOCOS.Partition
function fs.mount(path, partition)
    path = fs.canonical(path)
    assert(not fs.isMounted(partition), "already mounted")
    assert(fs.type(path) == "directory", "not a directory")
    assert(#fs.list(path) == 0, "not empty directory")
    local location = fs.canonical(path):sub(2)
    assert(not globalTranslation[location], "duplicate mountpoint")
    globalTranslation[location] = assert(fs.driverFor(partition), "missing driver")
end

---@param path string
function fs.unmount(path)
    assert(fs.isMount(path), "missing mountpoint")
    local location = fs.canonical(path):sub(2)
    globalTranslation[location] = nil
end

---@param path string
function fs.isMount(path)
    local location = fs.canonical(path):sub(2)
    return globalTranslation[location] ~= nil
end

---@return boolean, string
function fs.touch(path, permissions)
    local manager, truepath = fs.resolve(path)
    return manager:touch(truepath, permissions)
end

---@param path string
---@return boolean, string
function fs.mkdir(path, permissions)
    path = fs.canonical(path)
    if fs.type(fs.parentOf(path)) ~= "directory" then
        return false, "parent is not directory"
    end
    local manager, truePath = fs.resolve(path)
    return manager:mkdir(truePath, permissions)
end

---@param path string
---@return integer
function fs.permissionsOf(path)
    local manager, truePath = fs.resolve(path)
    return manager:permissionsOf(truePath)
end

---@param path string
---@param perms integer
function fs.setPermissionsOf(path, perms)
    local manager, truePath = fs.resolve(path)
    return manager:setPermissionsOf(truePath, perms)
end

---@param path string
---@return integer
function fs.modifiedTime(path)
    local manager, truePath = fs.resolve(path)
    return manager:modifiedTime(truePath)
end

---@param path string
---@return boolean, string
function fs.remove(path)
    if fs.isMount(path) then return false, "is mountpoint" end
    if fs.type(path) == "directory" then
        local l, err = fs.list(path)
        if err then return false, err end
        if #l > 0 then return false, "directory not empty" end
    end
    local manager, truePath = fs.resolve(path)
    return manager:remove(truePath)
end

---@param partition KOCOS.Partition
---@param format string
---@param opts table?
---@return boolean, string?
function fs.format(partition, format, opts)
    for i=#fs.drivers,1,-1 do
        local driver = fs.drivers[i]
        local ok, err = driver.format(partition, format, opts)
        if ok then return true end
        if err then return false, err end
    end
    return false, "unsupported"
end

---@param tested string
---@param reference string
---@param autocomplete boolean
local function sameUuid(tested, reference, autocomplete)
    if autocomplete then
        return string.startswith(tested:gsub("%-", ""), reference)
    end
    return tested == reference
end

---@return KOCOS.Partition?
function fs.wholeDrivePartition(drive)
    drive = KOCOS.vdrive.proxy(drive) or drive
    if drive.type ~= "drive" then return end
    ---@type KOCOS.Partition
    return {
        name = drive.getLabel() or drive.address:sub(1, 6),
        drive = drive,
        uuid = drive.address,
        startByte = 0,
        byteSize = drive.getCapacity(),
        kind = "root",
        readonly = false,
        storedKind = drive.address,
    }
end

---@param opts {allowFullDrivePartition: boolean, mountedOnly: boolean}
---@return KOCOS.Partition[]
function fs.findAllPartitions(opts)
    local parts = {}
    for _, partition in fs.mountedPartitions() do
        table.insert(parts, partition)
    end

    if not opts.mountedOnly then
        for addr in component.list() do
            local drive = component.proxy(addr)
            local localParts = fs.getPartitions(drive)
            if opts.allowFullDrivePartition then
                local wholeDrive = fs.wholeDrivePartition(drive)
                if wholeDrive then
                    table.insert(parts, wholeDrive)
                end
            end
            for i=1,#localParts do
                table.insert(parts, localParts[i])
            end
        end
    end
    local dupeMap = {}
    local deduped = {}
    for i=1,#parts do
        local part = parts[i]
        if not dupeMap[part.uuid] then
            dupeMap[part.uuid] = true
            table.insert(deduped, part)
        end
    end
    return deduped
end

-- Supports autocomplete
---@param uuid string
---@param opts {autocomplete: boolean, allowFullDrivePartition: boolean, mountedOnly: boolean}?
---@return KOCOS.Partition?
function fs.partitionFromUuid(uuid, opts)
    opts = opts or {
        autocomplete = true,
        allowFullDrivePartition = true,
        mountedOnly = false,
    }

    local parts = fs.findAllPartitions(opts)
    for i=1,#parts do
        if sameUuid(parts[i].uuid, uuid, opts.autocomplete) then
            return parts[i]
        end
    end
    return nil
end

---@return fun(...): string?, KOCOS.Partition
function fs.mountedPartitions()
    return function(_, mountpoint)
        mountpoint = next(globalTranslation, mountpoint)
        ---@diagnostic disable-next-line: missing-return-value
        if not mountpoint then return end
        local manager = globalTranslation[mountpoint]
        return mountpoint, manager:getPartition()
    end
end

---@param partition KOCOS.Partition
---@return boolean, string
function fs.isMounted(partition)
    for mountpoint, part in fs.mountedPartitions() do
        if part.uuid == partition.uuid then
            return true, "/" .. mountpoint
        end
    end
    return false, ""
end

function fs.mountRoot()
    if globalTranslation[""] then return end
    local root = KOCOS.defaultRoot
    local parts = fs.getPartitions(component.proxy(root))
    ---@type KOCOS.Partition?
    local rootPart

    for i=1,#parts do
        if (parts[i].kind == "root") or (KOCOS.rootPart == parts[i].uuid) then
            if parts[i].uuid == (KOCOS.rootPart or parts[i].uuid) then
                rootPart = parts[i]
            end
        end
    end

    assert(rootPart, "missing root partition on " .. root)
    globalTranslation[""] = assert(fs.driverFor(rootPart), "MISSING ROOTFS DRIVER OH NO")
end

KOCOS.fs = fs

---@param path string
function KOCOS.readFile(path)
    local f = assert(fs.open(path, "r"))
    local data = ""
    while true do
        local chunk, err = fs.read(f, math.huge)
        if err then fs.close(f) error(err) end
        if not chunk then break end
        data = data .. chunk
    end
    fs.close(f)
    return data
end

local readCache = {}

---@param path string
-- May not always be accurate!
-- Intended to be used for dynamically linked libraries
---@return string
function KOCOS.readFileCached(path)
    if readCache[path] then
        local s = fs.size(path)
        if s ~= #readCache[path] then
            readCache[path] = KOCOS.readFile(path)
        end
    else
        readCache[path] = KOCOS.readFile(path)
    end
    return readCache[path]
end

KOCOS.log("Loaded filesystem")

KOCOS.defer(function()
    if KOCOS.ramImage then
        KOCOS.log("Parsing ramfs...")
        local image = KOCOS.ramfs.parse(KOCOS.ramImage)
        assert(image, "corrupted ram image")
        globalTranslation[""] = KOCOS.ramfs.manager(image)
        KOCOS.log("Mounted ramfs root")
    else
        fs.mountRoot()
        KOCOS.log("Mounted default root")
    end

    -- apparently it can be nil?
    if not computer.tmpAddress() then return end
    if not fs.exists("/tmp") then assert(fs.mkdir("/tmp")) end
    local tmpfs = component.proxy(computer.tmpAddress())
    local partitions = fs.getPartitions(tmpfs)
    fs.mount("/tmp", partitions[1])
    KOCOS.log("Mounted tmpfs")
end, 3)

local vdrive = {}

--- Literally just the drive component interface lol
---@class KOCOS.VDrive
---@field type "drive"
---@field slot integer
---@field address string
---@field getLabel fun(): string
---@field setLabel fun(label: string): string
---@field getCapacity fun(): integer
---@field getSectorSize fun(): integer
---@field getPlatterCount fun(): integer
---@field readByte fun(byte: integer): integer
---@field readSector fun(sector: integer): string
---@field writeByte fun(byte: integer, byte: integer)
---@field writeSector fun(sector: integer)

---@alias KOCOS.VDrive.Driver fun(proxy: table): KOCOS.VDrive?

---@type KOCOS.VDrive.Driver[]
vdrive.drivers = {}

---@param driver KOCOS.VDrive.Driver
function vdrive.addDriver(driver) table.insert(vdrive.drivers, driver) end

---@param proxy string|table
---@return KOCOS.VDrive?
function vdrive.proxy(proxy)
    if type(proxy) == "string" then proxy = component.proxy(proxy) end
    ---@cast proxy table
    if proxy.type == "drive" then return proxy end
    for i=#vdrive.drivers, 1, -1 do
        local drive = vdrive.drivers[i](proxy)
        if drive then return drive end
    end
end

function vdrive.list()
    ---@type {[string]: KOCOS.VDrive}
    local t = {}
    for addr in component.list() do
        t[addr] = vdrive.proxy(addr) -- if nil then it just doesnt store it lol
    end
    return pairs(t)
end

KOCOS.vdrive = vdrive

KOCOS.log("Loaded vdrive system")

local ramfs = {}

---@alias KOCOS.RamFS.Image {[string]: string | string[]}

---@alias KOCOS.RamFS.Parser fun(data: string): KOCOS.RamFS.Image?

---@type KOCOS.RamFS.Parser[]
ramfs.parsers = {}

---@param parser KOCOS.RamFS.Parser
function ramfs.addParser(parser)
    table.insert(ramfs.parsers, parser)
end

---@param data string
---@return KOCOS.RamFS.Image?
function ramfs.parse(data)
    for i=#ramfs.parsers, 1, -1 do
        local parser = ramfs.parsers[i]
        local image = parser(data)
        if image then return image end
    end
end

---@param image KOCOS.RamFS.Image
function ramfs.manager(image)
    local start = os.time()
    local uuid = KOCOS.testing.uuid()
    ---@type {[integer]: {data: string, cursor: integer}}
    local handles = {}
    return {
        open = function(_, path, mode)
            if mode ~= "r" then return nil, "bad mode" end
            local data = image[path]
            if type(data) ~= "string" then return nil, "bad path" end
            local fd = #handles
            while handles[fd] do fd = fd + 1 end
            handles[fd] = {
                data = data,
                cursor = 0,
            }
            return fd
        end,
        write = function()
            return false, "bad file descriptor"
        end,
        read = function(_, fd, len)
            local handle = handles[fd]
            if not handle then return nil, "bad file descriptor" end
            if len == math.huge then len = #handle.data end
            local chunk = handle.data:sub(handle.cursor+1, handle.cursor+len)
            handle.cursor = handle.cursor + #chunk
            if chunk == "" then return end
            return chunk
        end,
        seek = function(_, fd, whence, offset)
            local handle = handles[fd]
            if not handle then return nil, "bad file descriptor" end
            local size = #handle.data
            local cur = handle.cursor

            if whence == "set" then
                cur = offset
            elseif whence == "cur" then
                cur = cur + offset
            elseif whence == "end" then
                cur = size - offset
            end

            handle.cursor = math.clamp(cur, 0, size)
            return handle.cursor
        end,
        close = function(_, fd)
            handles[fd] = nil
            return true
        end,
        type = function(_, path)
            local data = image[path]
            if type(data) == "string" then
                return "file"
            elseif type(data) == "table" then
                return "directory"
            else
                return "missing"
            end
        end,
        list = function(_, path)
            local files = image[path]
            if type(files) ~= "table" then return nil, "not a directory" end
            return files
        end,
        size = function(_, path)
            local data = image[path]
            if type(data) == "string" then return #data end
            return 0
        end,
        remove = function(_, path)
            return false, "readonly"
        end,
        spaceUsed = function()
            return 0
        end,
        spaceTotal = function()
            return 0
        end,
        mkdir = function()
            return false, "readonly"
        end,
        touch = function()
            return false, "readonly"
        end,
        permissionsOf = function()
            local perms = KOCOS.perms
            return perms.encode(perms.ID_ALL, perms.BIT_READABLE, perms.ID_ALL, perms.BIT_READABLE)
        end,
        setPermissionsOf = function()
            return false, "readonly"
        end,
        modifiedTime = function()
            return start
        end,
        ioctl = function()
            error("unsupported")
        end,
        getPartition = function()
            ---@type KOCOS.Partition
            return {
                uuid = uuid,
                drive = {
                    type = "ramfs",
                    slot = -1,
                    address = uuid,
                    getLabel = function()
                        return "ramfs-" .. uuid:sub(1, 8)
                    end,
                    setLabel = function()
                        return "ramfs-" .. uuid:sub(1, 8)
                    end,
                },
                readonly = true,
                startByte = 0,
                byteSize = 0,
                kind = "root",
                name = "ramfs-" .. uuid:sub(1, 8),
                storedKind = "ramfs",
            }
        end,
    }
end

KOCOS.ramfs = ramfs

KOCOS.log("Loaded ramfs system")
