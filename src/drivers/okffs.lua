-- OKFFS
-- "Original KOCOS Fast File System" for when it works consistently
-- "Obfuscating Killer For File Systems" for when it breaks
-- "ok, ffs" for when it works again

--[[
Structs:

struct okffs_dir_entry {
  // NULL terminator is optional
  uint8_t name[32];
  // modified time in milliseconds
  uint64_t mtimeMS;
  uint16_t permissions;
  uint8_t ftype;
  uint24_t blockList;
  uint32_t fileSize;
  uint8_t reserved[14];
}

struct okffs_block_prefix {
    uint24_t next;
    uint16_t len;
}

struct okffs_header {
    char header[6] = "OKFFS\0";
    uint24_t nextFree;
    uint24_t freeList;
    uint24_t root;
    uint24_t activeBlockCount;
}

]]

---@class KOCOS.OKFFS.FileState
---@field path string
---@field entry KOCOS.OKFFS.Entry
---@field lastModification integer
---@field rc integer

---@class KOCOS.OKFFS.Handle
---@field state KOCOS.OKFFS.FileState
---@field mode "w"|"r"
---@field pos integer
-- Used to determine if cached stuff is valid
---@field syncedWith integer
---@field curBlock integer
---@field curOff integer
---@field lastPosition integer

---@class KOCOS.OKFFS.Driver
---@field partition KOCOS.Partition
---@field drive table
---@field start integer
---@field sectorSize integer
---@field capacity integer
---@field readonly boolean
---@field fileStates {[string]: KOCOS.OKFFS.FileState}
---@field handles {[integer]: KOCOS.OKFFS.Handle}
---@field sectorCache {sector: integer, data: string}[]
---@field maxSectorCacheLen integer
local okffs = {}
okffs.__index = okffs

local SECTOR_CACHE_LIMIT = 16*1024

---@param partition KOCOS.Partition
function okffs.create(partition)
    if partition.kind == "reserved" then return end -- fast ass skip
    if partition.drive.type ~= "drive" then return end
    local sectorSize = partition.drive.getSectorSize()
    local manager = setmetatable({
        partition = partition,
        drive = partition.drive,
        start = math.floor(partition.startByte / sectorSize) + 1,
        sectorSize = sectorSize,
        capacity = math.floor(partition.byteSize / sectorSize),
        readonly = partition.readonly,
        fileStates = {},
        handles = {},
        sectorCache = {},
        maxSectorCacheLen = math.floor(SECTOR_CACHE_LIMIT / sectorSize),
    }, okffs)
    -- Failed signature check
    if not manager:fetchState() then
        return
    end
    return manager
end

---@param sector integer
---@return string
function okffs:lowLevelReadSector(sector)
    for i=#self.sectorCache,1,-1 do
        local entry = self.sectorCache[i]
        if entry.sector == sector then
            return entry.data
        end
    end
    local sec = assert(self.drive.readSector(sector+self.start))
    table.insert(self.sectorCache, {
        sector = sector,
        data = sec,
    })
    while #self.sectorCache > self.maxSectorCacheLen do
        table.remove(self.sectorCache, 1)
    end
    return sec
end

---@param sector integer
---@param data string
function okffs:lowLevelWriteSector(sector, data)
    for i=#self.sectorCache,1,-1 do
        local entry = self.sectorCache[i]
        if entry.sector == sector then
            entry.data = data
            break
        end
    end
    self.drive.writeSector(sector+self.start, data)
end

function okffs:padToSector(data)
    return data .. string.rep("\0", self.sectorSize - #data)
end

---@return string
function okffs:readSectorBytes(sector, off, len)
    local sec = self:lowLevelReadSector(sector)
    local data = sec:sub(off+1, off+len)
    assert(#data == len, "bad offset + len")
    return data
end

function okffs:readUint24(sector, off)
    local bytes = self:readSectorBytes(sector, off, 3)
    local low, middle, high = string.byte(bytes, 1, 3)
    return low
    + middle * 0x100
    + high * 0x10000
end

local function uint24ToBytes(num)
    local low = num % 256
    local middle = math.floor(num / 0x100) % 256
    local high = math.floor(num / 0x10000) % 256

    return low, middle, high
end

---@param sector integer
---@param off integer
---@param len integer
---@return integer
function okffs:readUintN(sector, off, len)
    local n = 0
    local m = 1
    local b = self:readSectorBytes(sector, off, len)
    for i=1,len do
        n = n + b:byte(i, i) * m
        m = m * 256
    end
    return n
end


function okffs:writeUint24(sector, off, num)
    assert(num >= 0 and num < 2^24, "bad uint24")


    local bytes = string.char(uint24ToBytes(num))
    self:writeSectorBytes(sector, off, bytes)
end

local function uintNToBytes(num, len)
    -- Little endian btw
    local b = ""
    for _=1,len do
        b = b .. string.char(num % 256)
        num = math.floor(num / 256)
    end
    return b
end

function okffs:writeUintN(sector, off, num, len)
    assert(num >= 0 and num < 2^(len*8), "bad uint" .. (len*8))

    self:writeSectorBytes(sector, off, uintNToBytes(num, len))
end

function okffs:writeSectorBytes(sector, off, data)
    local sec = self:lowLevelReadSector(sector)
    local pre = sec:sub(1, off)
    local post = sec:sub(off+#data+1)
    local written = pre .. data .. post
    self:lowLevelWriteSector(sector, written)
end

okffs.signature = "OKFFS\0"

function okffs:fetchState()
    local header = self:readSectorBytes(0, 0, 6)
    if header ~= okffs.signature then return false end
    self.nextFree = self:readUint24(0, 6)
    self.freeList = self:readUint24(0, 9)
    self.root = self:readUint24(0, 12)
    self.activeBlockCount = self:readUint24(0, 15)
    return true
end

function okffs:saveState()
    local data = okffs.signature
    data = data .. string.char(uint24ToBytes(self.nextFree))
    data = data .. string.char(uint24ToBytes(self.freeList))
    data = data .. string.char(uint24ToBytes(self.root))
    data = data .. string.char(uint24ToBytes(self.activeBlockCount))
    data = self:padToSector(data)
    self:lowLevelWriteSector(0, data)
end

---@param partition KOCOS.Partition
---@param format string
---@param opts table?
---@return boolean, string?
function okffs.format(partition, format, opts)
    local drive = partition.drive
    if drive.type ~= "drive" then return false end
    if format ~= "okffs" then return false end
    opts = opts or {}
    local sectorSize = drive.getSectorSize()
    local blockSize = opts.blockSize or sectorSize
    if blockSize ~= sectorSize then return false end
    if blockSize >= (2^16 + 5) then return false, "illegal block size" end
    local sectorsPerBlock = blockSize / sectorSize
    if sectorsPerBlock ~= math.floor(sectorsPerBlock) then return false, "block size not sector aligned" end
    local off = math.floor(partition.startByte / sectorSize)
    local sector = ""
    -- Signature
    sector = sector .. okffs.signature
    -- Next free (block immediately after)
    sector = sector .. string.char(uint24ToBytes(1))
    -- Free list (empty)
    sector = sector .. string.char(uint24ToBytes(0))
    -- Root (unallocated)
    sector = sector .. string.char(uint24ToBytes(0))
    -- Active block count
    sector = sector .. string.char(uint24ToBytes(0))

    sector = sector .. string.rep("\0", sectorSize - #sector)
    drive.writeSector(off+1, sector)
    return true
end

---@return integer
function okffs:allocBlock()
    if self.freeList == 0 then
        local block = self.nextFree
        if block == self.capacity then
            error("out of space")
        end
        self.nextFree = self.nextFree + 1
        self.activeBlockCount = self.activeBlockCount + 1
        self:saveState()
        return block
    end
    local block = self.freeList
    self.freeList = self:readUint24(block, 0)
    self.activeBlockCount = self.activeBlockCount + 1
    self:saveState()
    return block
end

local NULL_BLOCK = 0

---@param block integer
function okffs:freeBlock(block)
    if block == 0 then return end -- Freeing NULL is fine
    self:writeUint24(block, 0, self.freeList)
    self.freeList = block
    self.activeBlockCount = self.activeBlockCount - 1
    self:saveState()
end

---@param block integer
function okffs:freeBlockList(block)
    if block == 0 then return end -- Freeing NULL is fine
    while block ~= NULL_BLOCK do
        local next = self:readUint24(block, 0)
        self:freeBlock(block)
        block = next
    end
end

function okffs:allocDirectoryBlock()
    local block = self:allocBlock()
    self:writeUint24(block, 0, 0) -- Next
    self:writeUintN(block, 3, 0, 2) -- File count
    return block
end

function okffs:allocFileBlock()
    local block = self:allocBlock()
    self:writeUint24(block, 0, 0) -- Next
    self:writeUintN(block, 3, 0, 2) -- Used bytes
    return block
end

---@type {[KOCOS.FileType]: integer}
local typeMap = {
    directory = 0,
    file = 1,
    missing = 2,
}

---@type {[integer]: KOCOS.FileType}
local invTypeMap = {
    [0] = "directory",
    "file",
    "missing",
}

-- See structs
local DIR_ENTRY_SIZE = 64

---@class KOCOS.OKFFS.Entry
---@field name string
---@field type KOCOS.FileType
---@field blockList integer
---@field permissions integer
---@field mtimeMS integer
---@field dirEntryBlock integer
---@field dirEntryOff integer
---@field fileSize integer

---@return KOCOS.OKFFS.Entry
function okffs:getDirectoryEntry(dirBlock, off)
    local name = self:readSectorBytes(dirBlock, off, 32)
    local terminator = name:find("\0", nil, true)
    if terminator then
        name = name:sub(1, terminator-1)
    end

    local mtimeMS = self:readUintN(dirBlock, off+32, 8)
    local permissions = self:readUintN(dirBlock, off+40, 2)
    local ftype = self:readUintN(dirBlock, off+42, 1)
    local blockList = self:readUint24(dirBlock, off+43)
    local fileSize = self:readUintN(dirBlock, off+46, 4)

    ---@type KOCOS.OKFFS.Entry
    return {
        name = name,
        type = invTypeMap[ftype],
        blockList = blockList,
        permissions = permissions,
        mtimeMS = mtimeMS,
        dirEntryBlock = dirBlock,
        dirEntryOff = off,
        fileSize = fileSize,
    }
end

---@param entry KOCOS.OKFFS.Entry
---@return string
function okffs:encodeDirectoryEntry(entry)
    assert(#entry.name <= 32, "name too big")
    assert(#entry.name > 0, "missing name")
    assert(not string.find(entry.name, "[/%z\\]"), "invalid name")
    local data = ""
    data = data .. entry.name .. string.rep("\0", 32 - #entry.name)
    data = data .. uintNToBytes(entry.mtimeMS, 8)
    data = data .. uintNToBytes(entry.permissions, 2)
    data = data .. string.char(typeMap[entry.type])
    data = data .. string.char(uint24ToBytes(entry.blockList))
    data = data .. uintNToBytes(entry.fileSize, 4)
    data = data .. string.rep("\0", 14)
    return data
end

---@param entry KOCOS.OKFFS.Entry
function okffs:saveDirectoryEntry(entry)
    if entry.dirEntryBlock == NULL_BLOCK then return end
    self:writeSectorBytes(entry.dirEntryBlock, entry.dirEntryOff, self:encodeDirectoryEntry(entry))
end

---@param dirBlock integer
---@param name string
---@return KOCOS.OKFFS.Entry?
function okffs:queryDirectoryEntry(dirBlock, name)
    while true do
        if dirBlock == NULL_BLOCK then return end
        local next = self:readUint24(dirBlock, 0)
        local len = self:readUintN(dirBlock, 3, 2)
        for i=1,len do
            local off = i * DIR_ENTRY_SIZE
            local entry = self:getDirectoryEntry(dirBlock, off)
            if entry.name == name then
                return entry
            end
        end
        dirBlock = next
    end
end

---@param dirBlock integer
---@param name string
function okffs:removeDirectoryEntry(dirBlock, name)
    local entry = self:queryDirectoryEntry(dirBlock, name)
    -- nothing to delete
    if not entry then return end
    self:freeBlockList(entry.blockList)
    -- If it works it works
    self:writeUintN(entry.dirEntryBlock, entry.dirEntryOff, 0, DIR_ENTRY_SIZE)
end

---@Param dirBlock integer
---@param entry KOCOS.OKFFS.Entry
--- Mutates entry to store its new position
function okffs:addDirectoryEntry(dirBlock, entry)
    local maxLen = (self.sectorSize / DIR_ENTRY_SIZE) - 1
    while true do
        local next = self:readUint24(dirBlock, 0)
        local len = self:readUintN(dirBlock, 3, 2)
        if len < maxLen then
            len = len + 1
            self:writeUintN(dirBlock, 3, len, 2)
            entry.dirEntryBlock = dirBlock
            entry.dirEntryOff = len * DIR_ENTRY_SIZE
            self:saveDirectoryEntry(entry)
            return
        else
            for i=1,len do
                local found = self:getDirectoryEntry(dirBlock, i * DIR_ENTRY_SIZE)
                if found.name == "" then
                    -- Actually, valid space
                    entry.dirEntryBlock = dirBlock
                    entry.dirEntryOff = i * DIR_ENTRY_SIZE
                    self:saveDirectoryEntry(entry)
                    return
                end
            end
            if next == NULL_BLOCK then
                next = self:allocDirectoryBlock()
                self:writeUint24(dirBlock, 0, next)
            end
            dirBlock = next
        end
    end
end

---@param dirBlock integer
---@return string[]
function okffs:listDirectoryEntries(dirBlock)
    ---@type string[]
    local arr = {}
    while true do
        if dirBlock == NULL_BLOCK then break end
        local next = self:readUint24(dirBlock, 0)
        local len = self:readUintN(dirBlock, 3, 2)
        for i=1,len do
            local off = i * DIR_ENTRY_SIZE
            local entry = self:getDirectoryEntry(dirBlock, off)
            if entry.name ~= "" then
                if entry.type == "directory" then
                    table.insert(arr, entry.name .. "/")
                else
                    table.insert(arr, entry.name)
                end
            end
        end
        dirBlock = next
    end
    return arr
end

function okffs:ensureRoot()
    if self.root == NULL_BLOCK then
        self.root = self:allocDirectoryBlock()
        self:saveState()
    end
end

---@return KOCOS.OKFFS.Entry?
function okffs:entryOf(path)
    self:ensureRoot()
    ---@type KOCOS.OKFFS.Entry
    local entry = {
        name = "/",
        dirEntryBlock = NULL_BLOCK,
        dirEntryOff = 0,
        permissions = 2^16-1,
        type = "directory",
        blockList = self.root,
        mtimeMS = 0,
        fileSize = 0,
    }
    ---@type string[]
    local parts = string.split(path, "/")
    for i=#parts,1,-1 do
        if parts[i] == "" then table.remove(parts, i) end
    end
    while #parts > 0 do
        -- bad path
        if entry.type ~= "directory" then return nil end
        local name = table.remove(parts, 1)
        local subentry = self:queryDirectoryEntry(entry.blockList, name)
        if not subentry then return nil end
        entry = subentry
    end
    return entry
end

function okffs:spaceUsed()
    -- +1 cuz the header takes up 1 block
    return (self.activeBlockCount + 1) * self.sectorSize
end

function okffs:spaceTotal()
    return self.capacity * self.sectorSize
end

function okffs:isReadOnly(path)
    return self.readonly
end

function okffs:getPartition()
    return self.partition
end

---@param path string
function okffs:parentOf(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    path = path:reverse()
    local l = path:find("/", nil, true)
    if l then return path:sub(l+1):reverse() end
    return ""
end

---@param path string
function okffs:nameOf(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    path = path:reverse()
    local l = path:find("/", nil, true)
    if l then path = path:sub(1, l-1) end
    return path:reverse()
end

---@param parent string
---@param entry KOCOS.OKFFS.Entry
---@return boolean, string
function okffs:mkentry(parent, entry)
    self:ensureRoot()
    local parentEntry = self:entryOf(parent)
    if not parentEntry then return false, "missing parent" end
    if parentEntry.type ~= "directory" then return false, "bad parent" end
    if parentEntry.blockList == NULL_BLOCK then
        parentEntry.blockList = self:allocDirectoryBlock()
        self:saveDirectoryEntry(parentEntry)
    end
    if self:queryDirectoryEntry(parentEntry.blockList, entry.name) then return false, "duplicate" end
    ---@type KOCOS.OKFFS.Entry
    self:addDirectoryEntry(parentEntry.blockList, entry)
    return true, ""
end

function okffs:mkdir(path, permissions)
    local parent = self:parentOf(path)
    local name = self:nameOf(path)
    return self:mkentry(parent, {
        name = name,
        permissions = permissions,
        blockList = NULL_BLOCK,
        mtimeMS = 0,
        type = "directory",
        dirEntryBlock = 0,
        dirEntryOff = 0,
        fileSize = 0,
    })
end

function okffs:touch(path, permissions)
    local parent = self:parentOf(path)
    local name = self:nameOf(path)
    return self:mkentry(parent, {
        name = name,
        permissions = permissions,
        blockList = NULL_BLOCK,
        mtimeMS = 0,
        type = "file",
        dirEntryBlock = 0,
        dirEntryOff = 0,
        fileSize = 0,
    })
end

function okffs:permissionsOf(path)
    local entry = self:entryOf(path)
    if entry then return entry.permissions end
    return 2^16-1
end

function okffs:sizeOfBlockList(block)
    local n = 0
    while true do
        if block == NULL_BLOCK then break end
        n = n + 1
        block = self:readUint24(block, 0)
    end
    return n * self.sectorSize
end

function okffs:size(path)
    local entry = self:entryOf(path)
    if entry then return entry.fileSize end
    return 0
end

function okffs:type(path)
    local entry = self:entryOf(path)
    if entry then return entry.type end
    return "missing"
end

function okffs:list(path)
    local entry = self:entryOf(path)
    if not entry then return nil, "missing" end
    if entry.type ~= "directory" then return nil, "not directory" end
    return self:listDirectoryEntries(entry.blockList)
end

function okffs:remove(path)
    if self.fileStates[path] then
        return false, "in use"
    end
    local parent = self:parentOf(path)
    local name = self:nameOf(path)
    local parentEntry = self:entryOf(parent)
    if not parentEntry then return false, "missing" end
    if parentEntry.type ~= "directory" then return false, "bad path" end
    local entry = self:queryDirectoryEntry(parentEntry.blockList, name)
    if not entry then return false, "missing" end
    if entry.type == "directory" then
        if #self:listDirectoryEntries(entry.blockList) > 0 then return false, "not empty" end
    end
    self:removeDirectoryEntry(parentEntry.blockList, name)
    return true
end

---@return KOCOS.OKFFS.FileState?, string
function okffs:getFileState(path)
    if self.fileStates[path] then
        local state = self.fileStates[path]
        state.rc = state.rc + 1
        return state, ""
    end
    local entry = self:entryOf(path)
    if not entry then return nil, "missing" end
    if entry.type ~= "file" then return nil, "not file" end
    ---@type KOCOS.OKFFS.FileState
    local state = {
        path = path,
        entry = entry,
        rc = 1,
        lastModification = math.huge,
    }
    return state, ""
end

---@param handle KOCOS.OKFFS.Handle
function okffs:recordModification(handle)
    handle.state.lastModification = handle.state.lastModification + 1
    -- we are the last modification
    handle.syncedWith = handle.state.lastModification
end

function okffs:open(path, mode)
    local state, err = self:getFileState(path)
    if not state then return nil, err end
    ---@type KOCOS.OKFFS.Handle
    local handle = {
        state = state,
        pos = 0,
        mode = mode,
        -- Default cache stuff
        curBlock = NULL_BLOCK,
        curOff = 0,
        lastPosition = 0,
        syncedWith = state.lastModification,
    }
    self:clearHandleCache(handle)
    local fd = #self.handles
    while self.handles[fd] do fd = fd + 1 end
    self.handles[fd] = handle
    if mode == "w" then
        local entry = handle.state.entry
        self:freeBlockList(entry.blockList)
        entry.fileSize = 0
        entry.blockList = NULL_BLOCK
        self:saveDirectoryEntry(entry)

        -- we did a modification!!!!
        self:recordModification(handle)
    end
    return fd
end

---@param handle KOCOS.OKFFS.Handle
function okffs:clearHandleCache(handle)
    handle.curBlock = NULL_BLOCK
end

---@param handle KOCOS.OKFFS.Handle
function okffs:ensureSync(handle)
    if handle.syncedWith ~= handle.state.lastModification then
        -- Other handle fucked over our cache
        self:clearHandleCache(handle)
        handle.syncedWith = handle.state.lastModification
    end
end

---@param handle KOCOS.OKFFS.Handle
---@param position integer
function okffs:computeSeek(handle, position)
    self:ensureSync(handle)
    local curBlock = handle.curBlock
    local curOff = handle.curOff
    if curBlock == NULL_BLOCK then
        curBlock = handle.state.entry.blockList
        curOff = 0 -- just in case
        handle.lastPosition = 0
    end

    curOff = curOff + position - handle.lastPosition
    if position < handle.lastPosition then
        curBlock = handle.state.entry.blockList
        curOff = position
    end

    while curOff > 0 do
        local next = self:readUint24(curBlock, 0)
        local len = self:readUintN(curBlock, 3, 2)
        -- Being past the last byte of the last block is a condition write expects
        -- Read accounts for it
        if curOff <= len then break end
        curOff = curOff - len
        curBlock = next
    end

    handle.curBlock = curBlock
    handle.curOff = curOff
    handle.lastPosition = position
    handle.syncedWith = handle.state.lastModification
end

---@param handle KOCOS.OKFFS.Handle
function okffs:getSeekBlockAndOffset(handle)
    self:ensureSync(handle)
    if handle.curBlock == NULL_BLOCK or handle.lastPosition ~= handle.pos then
        self:computeSeek(handle, handle.pos)
    end
    return handle.curBlock, handle.curOff
end

---@param fileBlockList integer
function okffs:getByteLength(fileBlockList)
    local size = 0
    local block = fileBlockList
    while true do
        if block == NULL_BLOCK then break end
        local next = self:readUint24(block, 0)
        local len = self:readUintN(block, 3, 2)
        size = size + len
        block = next
    end
    return size
end

---@param handle KOCOS.OKFFS.Handle
function okffs:getHandleSize(handle)
    return handle.state.entry.fileSize
end

---@param amount integer
function okffs:recommendedMemoryFor(amount)
    return self:spaceNeededFor(amount) * 3 -- internal copies lol
end

---@param amount integer
function okffs:spaceNeededFor(amount)
    local dataPerBlock = self.sectorSize - 5 -- block prefix is next (3 bytes) + len (2 bytes)
    local blocksNeeded = math.ceil(amount / dataPerBlock)
    return blocksNeeded * self.sectorSize
end

function okffs:appendToBlockList(curBlock, data)
    local dataPerSector = self.sectorSize - 5
    while #data > 0 do
        local next = self:readUint24(curBlock, 0)
        local len = self:readUintN(curBlock, 3, 2)
        local remaining = dataPerSector - len

        local chunk = ""
        if #data <= remaining then
            -- Fast case
            chunk = data
            data = ""
        else
            -- Slow case
            chunk = data:sub(1, remaining)
            data = data:sub(remaining+1)
        end
        local old = self:readSectorBytes(curBlock, 5, len)
        len = len + #chunk
        local bin = uintNToBytes(next, 3) .. uintNToBytes(len, 2) .. old .. chunk
        bin = self:padToSector(bin)
        self:lowLevelWriteSector(curBlock, bin)

        if #data == 0 then break end

        local afterwards = next
        next = self:allocFileBlock()
        self:writeUint24(next, 0, afterwards)
        self:writeUint24(curBlock, 0, next)

        curBlock = next
    end
end

---@param curBlock integer
---@param curOff integer
---@param count integer
function okffs:readFileBlockList(curBlock, curOff, count)
    local data = ""
    while #data < count do
        if curBlock == NULL_BLOCK then break end
        local next = self:readUint24(curBlock, 0)
        local len = self:readUintN(curBlock, 3, 2)
        if curOff < len then
            data = data .. self:readSectorBytes(curBlock, 5 + curOff, len - curOff)
        end
        curBlock = next
        curOff = 0
    end
    if #data > count then data = data:sub(1, count) end
    return data
end

---@param fd integer
---@param data string
function okffs:write(fd, data)
    local handle = self.handles[fd]
    if not handle then return false, "bad file descriptor" end
    if computer.freeMemory() < self:recommendedMemoryFor(#data) then
        -- inconvenient OOMs may lead to corrupted data
        return false, "dangerously low ram"
    end
    -- once defragmenting is done, we could try to defragment here
    if self:spaceTotal() - self:spaceUsed() < self:spaceNeededFor(#data) then
        -- a failing block allocation during a write could corrupt data
        return false, "out of space"
    end
    self:ensureSync(handle)
    local entry = handle.state.entry
    if entry.blockList == NULL_BLOCK then
        entry.blockList = self:allocFileBlock()
        self:saveDirectoryEntry(entry)
        self:recordModification(handle)
    end
    -- we gonna modify it
    local curBlock, curOff = self:getSeekBlockAndOffset(handle)
    do
        local len = self:readUintN(curBlock, 3, 2)
        if curOff < len then
            -- when they're equal, we insert right after
            -- when they're not, we need to append
            local extradata = self:readSectorBytes(curBlock, 5 + curOff, len - curOff)
            data = data .. extradata -- we do it here in case of OOM
            self:writeUintN(curBlock, 3, curOff, 2) -- make them equal
        end
        self:appendToBlockList(curBlock, data)
        handle.state.entry.fileSize = handle.state.entry.fileSize + #data
        self:saveDirectoryEntry(handle.state.entry)
    end
    handle.pos = handle.pos + #data
    self:recordModification(handle)
    return true
end


---@param fd integer
---@param len integer
function okffs:read(fd, len)
    -- TODO: make readFileBlockList support math.huge lengths
    if len == math.huge then len = 16384 end
    local handle = self.handles[fd]
    if not handle then return false, "bad file descriptor" end
    self:ensureSync(handle)
    local curBlock, curOff = self:getSeekBlockAndOffset(handle)
    local data = self:readFileBlockList(curBlock, curOff, len)
    handle.pos = handle.pos + #data
    if #data == 0 then return nil, nil end
    return data
end

---@param fd integer
---@param whence "set"|"cur"|"end"
---@param off integer
function okffs:seek(fd, whence, off)
    local handle = self.handles[fd]
    if not handle then return nil, "bad file descriptor" end
    local size = self:getHandleSize(handle)
    local pos = handle.pos
    if whence == "set" then
        pos = off
    elseif whence == "cur" then
        pos = pos + off
    elseif whence == "end" then
        pos = size - off
    end
    handle.pos = math.max(0, math.min(pos, size))
    return handle.pos
end

function okffs:close(fd)
    local handle = self.handles[fd]
    if not handle then return false, "bad file descriptor" end
    self.handles[fd] = nil
    handle.state.rc = handle.state.rc - 1
    if handle.state.rc <= 0 then
        self.fileStates[handle.state.path] = nil
    end
    return true
end

KOCOS.fs.addDriver(okffs)

KOCOS.test("OKFFS driver", function()
    local drive = KOCOS.testing.drive(512, 16384)
    ---@type KOCOS.Partition
    local partition = {
        name = "Test partition",
        drive = drive,
        readonly = false,
        startByte = 0,
        byteSize = drive.getCapacity(),
        kind = "user",
        uuid = KOCOS.testing.uuid(),
        storedKind = KOCOS.testing.uuid(),
    }

    assert(okffs.create(partition) == nil)

    assert(okffs.format(partition, "okffs"))

    local manager = assert(okffs.create(partition), "formatting failed")

    assert(manager:spaceTotal() == drive.getCapacity())

    assert(manager.nextFree == 1, "invalid nextfree")
    assert(manager.freeList == 0, "free list should not be allocated")
    assert(manager.root == 0, "root should not be allocated")

    local a, b, c = manager:allocBlock(), manager:allocBlock(), manager:allocBlock()
    assert(manager.nextFree == 4, "block allocator broken nextfree")
    assert(a == 1 and b == 2 and c == 3, "block allocator is behaving unexpectedly")
    manager:freeBlock(b)
    assert(manager.activeBlockCount == 2, "incorrectly tracked active block count")
    local d = manager:allocBlock()
    assert(b == d, "block allocator is not reusing blocks")
    assert(manager.nextFree == 4, "block allocator is wasting space pointlessly")
    assert(manager.activeBlockCount == 3, "incorrectly tracked active block count")

    manager:freeBlock(a)
    manager:freeBlock(b)
    manager:freeBlock(d)

    assert(manager.activeBlockCount == 0, "incorrectly tracked active block count")

    -- Nuke old state
    okffs.format(partition, "okffs")
    manager = assert(okffs.create(partition), "formatting failed")

    local perms = math.random(0, 2^16-1)
    assert(manager:touch("test", perms))
    assert(manager:mkdir("data", perms))
    assert(manager:touch("data/stuff", perms))
    assert(manager:touch("data/other", perms))
    assert(manager:permissionsOf("test") == perms, "perms dont work")
    assert(manager:permissionsOf("data") == perms, "perms dont work")

    KOCOS.testing.expectSameSorted(assert(manager:list("")), {
        "test",
        "data/",
    })

    KOCOS.testing.expectSameSorted(assert(manager:list("data")), {
        "stuff",
        "other",
    })

    local spaceUsed = manager:spaceUsed()
    assert(manager:mkdir("spam", perms))
    for i=1,100 do
        -- SPAM THIS BITCH
        assert(manager:touch("spam/" .. i, perms))
        assert(manager:type("spam/" .. i) == "file")
    end
    -- should fail as it is non-empty
    KOCOS.testing.expectFail(assert, manager:remove("spam"))
    for i=1,100 do
        -- SPAM THIS BITCH
        assert(manager:remove("spam/" .. i))
        assert(manager:type("spam/" .. i) == "missing")
    end
    assert(manager:remove("spam"))
    assert(manager:spaceUsed() == spaceUsed, "space is getting leaked (" .. (spaceUsed - manager:spaceUsed()) .. " blocks)")

    local test = assert(manager:open("test", "w"))
    assert(manager:seek(test, "cur", 0) == 0, "bad initial position")

    local smallData = "Hello, world!"
    local bigData = ""
    do
        local bytes = {}
        for _=1,1024 do
            table.insert(bytes, math.random(0, 255))
        end
        bigData = string.char(table.unpack(bytes))
    end
    assert(manager:write(test, smallData))
    assert(manager:seek(test, "cur", 0) == #smallData, "bad current position")
    assert(manager:seek(test, "set", 0) == 0, "seeking is messing us up")
    assert(manager:read(test, #smallData) == smallData, "reading data back is wrong")
    assert(manager:seek(test, "set", 0))
    assert(manager:seek(test, "end", 0) == #smallData, "bad end position")
    assert(manager:write(test, smallData))
    assert(manager:seek(test, "end", 0) == #smallData * 2, "bad file size")
    assert(manager:read(test, math.huge) == nil, "reading does not EOF")
    assert(manager:seek(test, "set", 0))
    assert(manager:read(test, 2 * #smallData) == string.rep(smallData, 2), "bad appends")
    local smallFileData = string.rep(smallData, 2, "___")
    assert(manager:seek(test, "set", #smallData))
    assert(manager:write(test, "___"))
    assert(manager:seek(test, "set", 0))
    assert(manager:read(test, #smallFileData) == smallFileData, "bad inserts")
    assert(manager:seek(test, "set", 0))
    assert(manager:write(test, bigData))
    assert(manager:seek(test, "set", 0))
    assert(manager:read(test, #bigData + #smallFileData) == bigData .. smallFileData, "bad prepends from big data")

    assert(manager:close(test))
    assert(next(manager.handles) == nil, "handles leaked")
    assert(next(manager.fileStates) == nil, "file states leaked")
end)

KOCOS.defer(function()
    if not KOCOS.fs.exists("/tmp") then return end
    -- 2^18 means 256KiB
    local drive = KOCOS.testing.drive(512, 2^18, "OKFFS tmp drive")
    ---@type KOCOS.Partition
    local partition = {
        name = "OKFFS mount",
        drive = drive,
        kind = "user",
        startByte = 0,
        byteSize = drive.getCapacity(),
        readonly = false,
        storedKind = KOCOS.testing.uuid(),
        uuid = KOCOS.testing.uuid(),
    }
    okffs.format(partition, "okffs")
    KOCOS.fs.mount("/tmp", partition)
    KOCOS.log("Mounted OKFFS tmp")
end, 1)

KOCOS.log("OKFFS driver loaded")
