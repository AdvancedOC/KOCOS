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
  uint8_t reserved[18];
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

---@class KOCOS.OKFFSDriver
---@field partition KOCOS.Partition
---@field drive table
---@field start integer
---@field sectorSize integer
---@field capacity integer
---@field readonly boolean
local okffs = {}
okffs.__index = okffs

---@param partition KOCOS.Partition
function okffs.create(partition)
    if partition.kind == "reserved" then return end -- fast ass skip
    if partition.drive.type ~= "drive" then return end
    local sectorSize = partition.drive.getSectorSize()
    local manager = setmetatable({
        partition = partition,
        drive = partition.drive,
        start = math.floor(partition.startByte / sectorSize),
        sectorSize = sectorSize,
        capacity = math.floor(partition.byteSize / sectorSize),
        readonly = partition.readonly,
    }, okffs)
    -- Failed signature check
    if not manager:fetchState() then
        return
    end
    return manager
end

---@return string
function okffs:readSectorBytes(sector, off, len)
    local sec = assert(self.drive.readSector(sector+self.start))
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
    for i=1,len do
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
    local sec = assert(self.drive.readSector(sector+self.start))
    local pre = sec:sub(1, off)
    local post = sec:sub(off+#data+1)
    local written = pre .. data .. post
    assert(self.drive.writeSector(sector+self.start, written))
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
    self:writeUint24(0, 6, self.nextFree)
    self:writeUint24(0, 9, self.freeList)
    self:writeUint24(0, 12, self.root)
    self:writeUint24(0, 15, self.activeBlockCount)
end

function okffs.format(drive, off)
    off = off or 0
    local sectorSize = drive.getSectorSize()
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
    assert(drive.writeSector(off, sector))
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

---@class KOCOS.OKFFSEntry
---@field name string
---@field type KOCOS.FileType
---@field blockList integer
---@field permissions integer
---@field mtimeMS integer
---@field dirEntryBlock integer
---@field dirEntryOff integer

---@return KOCOS.OKFFSEntry
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

    ---@type KOCOS.OKFFSEntry
    return {
        name = name,
        type = invTypeMap[ftype],
        blockList = blockList,
        permissions = permissions,
        mtimeMS = mtimeMS,
        dirEntryBlock = dirBlock,
        dirEntryOff = off,
    }
end

---@param entry KOCOS.OKFFSEntry
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
    data = data .. string.rep("\0", 18)
    return data
end

---@param entry KOCOS.OKFFSEntry
function okffs:saveDirectoryEntry(entry)
    if entry.dirEntryBlock == NULL_BLOCK then return end
    self:writeSectorBytes(entry.dirEntryBlock, entry.dirEntryOff, self:encodeDirectoryEntry(entry))
end

---@param dirBlock integer
---@param name string
---@return KOCOS.OKFFSEntry?
function okffs:queryDirectoryEntry(dirBlock, name)
    if dirBlock == 48 then error("e") end
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

---@Param dirBlock integer
---@param entry KOCOS.OKFFSEntry
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
            break
        else
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
            if entry.type == "directory" then
                table.insert(arr, entry.name .. "/")
            else
                table.insert(arr, entry.name)
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

---@return KOCOS.OKFFSEntry?
function okffs:entryOf(path)
    self:ensureRoot()
    ---@type KOCOS.OKFFSEntry
    local entry = {
        name = "/",
        dirEntryBlock = NULL_BLOCK,
        dirEntryOff = 0,
        permissions = 2^16-1,
        type = "directory",
        blockList = self.root,
        mtimeMS = 0,
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
---@param entry KOCOS.OKFFSEntry
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
    ---@type KOCOS.OKFFSEntry
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
    if entry then return self:sizeOfBlockList(entry.blockList) end
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

    okffs.format(drive)

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
    okffs.format(drive)
    manager = assert(okffs.create(partition), "formatting failed")

    local perms = math.random(0, 2^16-1)
    assert(manager:touch("test", perms))
    assert(manager:mkdir("data", perms))
    assert(manager:touch("data/stuff", perms))
    assert(manager:touch("data/other", perms))

    KOCOS.testing.expectSameSorted(assert(manager:list("")), {
        "test",
        "data/",
    })

    KOCOS.testing.expectSameSorted(assert(manager:list("data")), {
        "stuff",
        "other",
    })
end)

KOCOS.defer(function()
    if not KOCOS.fs.exists("/tmp") then return end
    local drive = KOCOS.testing.drive(512, 16384, "OKFFS tmp drive")
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
    okffs.format(drive)
    KOCOS.fs.mount("/tmp", partition)
    KOCOS.log("Mounted OKFFS tmp")
end, 1)
