--- Distributable OKFFS implementation
--- Supports reading files in both streams and as strings, listing directories, getting file types, basic info and formatting.
--- Errors are raised via error()
--- The functions provided are:
--- okffs.makePartition(drive, off) to make a partition, as a drive with an offset (in sectors)
--- okffs.check(partition) to check if a partition has the OKFFS header
--- okffs.entryOf(partition, path) to return all information about a path
--- okffs.type(partition, path) to get the type of an entry, either "file", "directory" or, if it does not exist, "missing"
--- okffs.iter(partition, path) to get an iterator over a directory in OKFFS
--- okffs.list(partition, path) to list a directory in OKFFS
--- okffs.read(partition, path) to get an iterator over the chunks of the file at path
--- okffs.readAll(partition, path) to get a string containing the file's contents
--- okffs.readSub(partition, path, i, j) to get a string containing parts of a file's contents, from i (starting at 1) to j (with the file size as the last)
--- okffs.format(partition, structure) to format an OKFFS drive. structure can be passed in to format files and directories there. See its comments for details.
local okffs = {}

local NULL_BLOCK = 0
local DIR_ENTRY_SIZE = 64

local FTYPE_DIR = 0
local FTYPE_FILE = 1
local SLASH_BYTE = string.byte('/')

---@param bytes string
---@param off integer
---@param len integer
---@return integer
local function readUintLE(bytes, off, len)
    local n = 0
    for i=1,len do
        local x = bytes:byte(off+i, off+i)
        n = n + x * (256 ^ (i - 1))
    end
    return n
end

---@return string
local function readSector(partition, id)
    return partition.drive.readSector(partition.off + id)
end

function okffs.makePartition(drive, off)
    return {
        drive = drive,
        off = off,
    }
end

---@return integer
local function getRootBlock(partition)
    if partition.rootCache then return partition.rootCache end
    local data = readSector(partition, 0)
    local root = readUintLE(data, 12, 3)
    partition.rootCache = root
    return root
end

---@return integer, integer
local function getBlockPrefix(data)
    return readUintLE(data, 0, 3), readUintLE(data, 3, 2)
end

---@return integer
local function blockSizeOf(partition)
    if partition.blockSizeCache then return partition.blockSizeCache end
    local sectorSize = partition.drive.getSectorSize()
    partition.blockSizeCache = sectorSize
    return sectorSize
end

local function dirEntries(partition, block)
    local i = 1
    return function()
        while true do
            if block == NULL_BLOCK then return end
            local data = readSector(partition, block)
            local next, len = getBlockPrefix(data)
            local off = i * DIR_ENTRY_SIZE
            local name = data:sub(off, off+32)
            local terminator = name:find("\0", nil, true)
            if terminator then name = name:sub(1, terminator-1) end
            local mtimeMS = readUintLE(data, off+32, 8)
            local permissions = readUintLE(data, off+40, 2)
            local ftype = readUintLE(data, off+42, 1)
            local blockList = readUintLE(data, off+43, 3)
            if i == len then
                i = 1
                block = next
            else
                i = i + 1
            end
            if #name > 0 then
                return {
                    name = name,
                    mtimeMS = mtimeMS,
                    permissions = permissions,
                    ftype = ftype,
                    blockList = blockList,
                }
            end
        end
    end
end

local function rootEntry(partition)
    return {
        name = "/",
        mtimeMS = 0,
        permissions = 2^16-1,
        ftype = 0,
        blockList = getRootBlock(partition),
    }
end

local function partsIter(_, path)
    if path == "" then return end
    local n = string.find(path, "/", nil, true)
    if not n then return "", path end
    return path:sub(n+1), path:sub(1,n-1)
end

local function partsOf(path)
    -- This is faster than allocating a substring
    if path:byte(1, 1) == SLASH_BYTE then path = path:sub(2) end
    -- We use Lua stateless iters cuz we fancy
    -- Also saves memory
    return partsIter, path, path
end

function okffs.check(partition)
    local superblock = readSector(partition, 0)
    return string.sub(superblock, 1, 6) == "OKFFS\0"
end

---@return {name: string, mtimeMS: integer, permissions: integer, ftype: integer, blockList: integer}?
function okffs.entryOf(partition, path)
    local entry = rootEntry(partition)
    for _, name in partsOf(path) do
        assert(entry.ftype == FTYPE_DIR, "attempt to access file inside file")
        local found = false
        for subentry in dirEntries(partition, entry.blockList) do
            if subentry.name == name then
                entry = subentry
                found = true
                break
            end
        end
        if not found then
            -- No entry, not found
            return nil
        end
    end
    return entry
end

function okffs.type(partition, path)
    local entry = okffs.entryOf(partition, path)
    if not entry then return "missing" end
    if entry.ftype == FTYPE_DIR then return "directory" end
    if entry.ftype == FTYPE_FILE then return "file" end
    error("Corrupted entry at " .. path)
end

function okffs.iter(partition, path)
    local entry = okffs.entryOf(partition, path)
    assert(entry, "not found")
    assert(entry.ftype == FTYPE_DIR, "not a directory")

    local iter = dirEntries(partition, entry.blockList)
    return function()
        local dirEntry = iter()
        if not dirEntry then return end
        local name = dirEntry.name
        if dirEntry.ftype == FTYPE_DIR then name = name .. "/" end
        return name
    end
end

function okffs.list(partition, path)
    ---@type string[]
    local t = {}
    for name in okffs.iter(partition, path) do
        table.insert(t, name)
    end
    return t
end

function okffs.read(partition, path)
    local entry = okffs.entryOf(partition, path)
    assert(entry, "not found")
    assert(entry.ftype == FTYPE_FILE, "not a file")

    local block = entry.blockList
    return function()
        if block == NULL_BLOCK then return end
        local data = readSector(partition, block)
        local next, len = getBlockPrefix(data)
        local chunk = data:sub(6, 5+len)
        block = next
        return chunk
    end
end

function okffs.readSub(partition, path, i, j)
    local x = 0
    local off = 0
    local data = ""
    for chunk in okffs.read(partition, path) do
        if x < i then
            x = x + #chunk
            if x >= i then
                off = x - i
            end
        end
        if x >= i then
            data = data .. chunk
        end
        if x >= j then break end
    end
    return data:sub(i+off,j+off)
end

function okffs.readAll(partition, path)
    local data = ""
    for chunk in okffs.read(partition, path) do
        data = data .. chunk
    end
    return data
end

--- structure is a directory structure.
--- A directory structure is a function. When called, it returns either nil (no more entries) or a table (directory entry).
--- Directory entries have a name field, a string which represents the entry's name,
--- a type field, which can be "file" or "directory", an optional permissions field, storing an integer in KOCOS permissions format (defaults to 2^16-1),
--- and a data field, which must be a string (or an iterator over string chunks) for files and another directory structure for directories.
function okffs.format(partition, structure)
end

-- If you want to use this in a single-file BIOS or bootloader, remove this line
return okffs
