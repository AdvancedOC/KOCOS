-- TODO: support symlinks

---@alias KOCOS.FileSystemDriver table

---@class KOCOS.File
---@field mode "w"|"r"
---@field refc integer
---@field kind "disk"|"memory"|"pipe"
---@field events KOCOS.EventSystem

---@class KOCOS.DiskFile: KOCOS.File
---@field kind "disk"
---@field fd any
---@field manager KOCOS.FileSystemDriver

---@class KOCOS.MemoryFile: KOCOS.File
---@field kind "memory"
---@field buffer string
---@field bufcap integer
---@field cursor integer

---@class KOCOS.PipeFile: KOCOS.File
---@field kind "pipe"
---@field output KOCOS.File
---@field input KOCOS.File

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

---@param mode "w"|"r"
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

---@param path string
---@param mode "w"|"r"
---@return KOCOS.DiskFile?, string
function fs.open(path, mode)
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
    local fd, err = manager:open(truepath)
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
    end
    return true, ""
end

---@param file KOCOS.File
---@param data string
---@return boolean, string
function fs.write(file, data)
    pcall(file.events.push, "write", data)
    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:write(file.fd, data)
    elseif file.kind == "memory" then
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
    end
    return false, "bad file"
end

---@param file KOCOS.File
---@param len integer
---@return string?, string?
function fs.read(file, len)
    pcall(file.events.push, "read", len)
    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:read(file.fd, len)
    elseif file.kind == "memory" then
        ---@cast file KOCOS.MemoryFile
        if file.mode == "w" then
            if len < #file.buffer then
                local chunk = file.buffer:sub(1, len)
                file.buffer = file.buffer:sub(len+1)
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
    end
    return nil, "bad file"
end

---@param file KOCOS.File
---@param whence "set"|"cur"|"end"
---@param offset integer
---@return integer?, string
function fs.seek(file, whence, offset)
    pcall(file.events.push, "seek", whence, offset)

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
    end

    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:seek(file.fd, whence, offset)
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
    end

    if file.kind == "disk" then
        ---@cast file KOCOS.DiskFile
        return file.manager:ioctl(file.fd, ...)
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
function fs.parentOf(path)
    local parts = string.split(fs.canonical(path), "%/")
    parts[#parts] = nil
    return "/" .. table.concat(parts, "/")
end

---@class KOCOS.Partition
---@field drive table
---@field startByte integer
---@field byteSize integer
---@field name string
---@field uuid string
---@field storedKind string
---@field kind "boot"|"root"|"user"
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

KOCOS.fs = fs

KOCOS.log("Loaded filesystem")

KOCOS.defer(function()
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
    KOCOS.log("Mounted default root")
end, 3)
