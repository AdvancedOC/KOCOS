-- OKFFS
-- "Original KOCOS Fast File System" for when it works consistently
-- "Obfuscating Killer For File Systems" for when it breaks
-- "ok, ffs" for when it works again

---@class KOCOS.OKFFSDriver
---@field drive table
---@field start integer
---@field sectorSize integer
---@field capacity integer
---@field readonly boolean
local okffs = {}
okffs.__index = okffs

---@param partition KOCOS.Partition
function okffs.create(partition)
    if partition.drive.type ~= "drive" then return end
    local sectorSize = partition.drive.getSectorSize()
    local manager = setmetatable({
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
    local bytes = self:readSectorBytes(sector+self.start, off, 3)
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

function okffs:writeUint24(sector, off, num)
    assert(num >= 0 and num < 2^24, "bad uint24")


    local bytes = string.char(uint24ToBytes(num))
    self:writeSectorBytes(sector, off, bytes)
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
    self:writeUint24(block, 3, 0) -- File count
    return block
end

function okffs:allocFileBlock()
    local block = self:allocBlock()
    self:writeUint24(block, 0, 0) -- Next
    self:writeUint24(block, 3, 0) -- Used bytes
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

-- 60 byte name, 1 byte type, 3 byte block
local DIR_ENTRY_SIZE = 64

---@param dirBlock integer
---@param name string
---@param type KOCOS.FileType
---@param block integer
function okffs:addDirectoryEntry(dirBlock, name, type, block)
    while true do
        local len = self:readUint24(dirBlock, 3)
        if (len+2)*DIR_ENTRY_SIZE > self.sectorSize then
            local next = self:readUint24(dirBlock, 0)
            if next == 0 then
                next = self:allocDirectoryBlock()
                self:writeUint24(dirBlock, 0, next)
            end
            dirBlock = next
        else
            -- We have the space
            len = len + 1
            self:writeUint24(dirBlock, 3, len)
            local idx = len
            local off = idx * DIR_ENTRY_SIZE
            self:writeSectorBytes(dirBlock, off, (name .. "\0"):sub(1, 60))
            self:writeSectorBytes(dirBlock, off + 60, string.char(typeMap[type]))
            self:writeUint24(dirBlock, off + 61, block)
            break
        end
    end
end

---@param dirBlock integer
---@param name string
---@return integer?, KOCOS.FileType
function okffs:queryDirectoryEntry(dirBlock, name)
    while true do
        if dirBlock == NULL_BLOCK then break end
        local nextBlock = self:readUint24(dirBlock, 0)
        local len = self:readUint24(dirBlock, 3)

        for i=1,len do
            local off = i * DIR_ENTRY_SIZE
            local entry = self:readSectorBytes(dirBlock, off, 60)
            local terminator = string.find(entry, "\0", nil, true)
            if terminator then
                entry = entry:sub(1, terminator-1)
            end
            if entry == name then
                -- WE FOUND IT!!!!!
                local type = invTypeMap[self:readSectorBytes(dirBlock, off+60, 1):byte()]
                local block = self:readUint24(dirBlock, off+61)
                if block == NULL_BLOCK then
                    if type == "directory" then
                        block = self:allocDirectoryBlock()
                    else
                        block = self:allocFileBlock()
                    end
                    self:writeUint24(dirBlock, off+61, block)
                end
                return block, type
            end
        end
        dirBlock = nextBlock
    end
    return nil, "missing"
end

---@param dirBlock integer
---@return string[]
function okffs:listDirectoryEntries(dirBlock)
    local all = {}
    while true do
        -- Yup, this works, fuck you
        if dirBlock == NULL_BLOCK then break end
        local nextBlock = self:readUint24(dirBlock, 0)
        local len = self:readUint24(dirBlock, 3)

        for i=1,len do
            local off = i * DIR_ENTRY_SIZE
            local name = self:readSectorBytes(dirBlock, off, 60)
            local terminator = string.find(name, "\0", nil, true)
            if terminator then
                name = name:sub(1, terminator-1)
            end
            local type = self:readSectorBytes(dirBlock, off+60, 1):byte()
            if invTypeMap[type] == "directory" then
                name = name .. "/"
            end
            table.insert(all, name)
        end
        dirBlock = nextBlock
    end
    return all
end

---@return integer?, KOCOS.FileType
function okffs:pathInfo(path)
    if self.root == 0 then
        self.root = self:allocDirectoryBlock()
        self:saveState()
    end
    return nil, "missing"
end

function okffs:spaceUsed()
    return self.activeBlockCount * self.sectorSize
end

function okffs:spaceTotal()
    return self.capacity * self.sectorSize
end

-- OKFFS does not have the concept of readonly files
-- Only readonly partitions.
function okffs:isReadOnly(_)
    return self.readonly
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
end)
