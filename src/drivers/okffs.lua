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

---@param block integer
function okffs:freeBlock(block)
    self:writeUint24(block, 0, self.freeList)
    self.freeList = block
    self.activeBlockCount = self.activeBlockCount - 1
    self:saveState()
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
