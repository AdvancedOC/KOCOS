-- LightFS
-- Lightweight File System
-- Great as a root, boot and backup.
-- Readers are easy to implement, and its designed to be fast
-- Very good for BIOSes, bootloaders and others.
-- Conventional, no `i` or `erase`.

--[[
// First sector. Rest of sector is 0'd.
// Sector IDs start from 0, not 1 like in OC drives.
// Its all little endian btw
// Block IDs also start from 0, though block 0 is the superblock.
struct superblock {
    char header[8] = "LightFS\0";
    uint24_t nextFreeBlock;
    uint24_t rootSector;
    uint24_t firstFreeSector; // first sector in free list.
    uint8_t mappingAlgorithm; // mapping algorithm used on the device
    uint24_t activeBlockCount;
};

enum mappingAlgorithm {
    INITIAL = 0,
};

struct block {
    uint24_t nextBlockSector; // sector of next block in block list. 0 for end 
    uint8_t data[]; // rest of sector
};

struct dirBlock {
    uint24_t nextBlockSector; // sector of next block in block list. 0 for end
    uint8_t entryCount;
    uint8_t padding[60]; // 0'd
};

struct freeBlock {
    uint24_t nextBlockSector; // once we free this, the next block to put in the free list, unless it is 0.
    uint24_t nextFreeSector; // sector of next block in the free list
};

enum ftype {
    FILE = 0,
    DIRECTORY = 1,
};

// directory blocklists are just like file blocklists, but the file contents are a sequence of dirEntries.
// 64 bytes
struct dirEntry {
    char name[32]; // NULL-terminated. Empty for deleted files.
    uint64_t mtimeMS;
    uint16_t permissions;
    uint8_t ftype;
    uint24_t firstBlockListSector;
    uint32_t fileSize;
    uint24_t blockCount; // to optimize activeBlockCount a lot
    uint8_t reserved[11]; // 0'd out
};
]]

local FTYPE_FILE = 0
local FTYPE_DIRECTORY = 1
local MAX_CACHE_SIZE = 65536
local DIRENT_SIZE = 64
local NAMESIZE = 32
local HEADER = "LightFS\0"

---@class KOCOS.LightFS.DirEntry
---@field name string
---@field mtimeMS integer
---@field permissions integer
---@field ftype integer
---@field firstBlockListSector integer
---@field fileSize integer
---@field blockCount integer

---@class KOCOS.LightFS.Driver
---@field nextFreeBlock integer
---@field rootSector integer
---@field firstFreeSector integer
---@field mappingAlgorithm integer
---@field activeBlockCount integer
---@field drive KOCOS.VDrive
---@field partition KOCOS.Partition
---@field sectorOffset integer
---@field maximumBlockCount integer
---@field cache {sector: integer, data: string}[]
---@field cacheCap integer
---@field sectorSize integer
local lightfs = {}
lightfs.__index = lightfs

---@param partition KOCOS.Partition
function lightfs.create(partition)
    if partition.kind == "reserved" then return end
    local drive = KOCOS.vdrive.proxy(partition.drive) or partition.drive
    if drive.type ~= "drive" then return end
    local sectorSize = drive.getSectorSize()

    local off = partition.startByte / sectorSize
    local rootSector = drive.readSector(1 + off)

    if rootSector:sub(1, 8) ~= HEADER then return end

    local nextFreeBlock = lightfs.decodeLE(rootSector, 8, 3)
    local rootDir = lightfs.decodeLE(rootSector, 11, 3)
    local firstFreeSector = lightfs.decodeLE(rootSector, 14, 3)
    local mappingAlgorithm = lightfs.decodeLE(rootSector, 17, 1)
    local activeBlockCount = lightfs.decodeLE(rootSector, 18, 3)

    return setmetatable({
        nextFreeBlock = nextFreeBlock,
        rootSector = rootDir,
        firstFreeSector = firstFreeSector,
        mappingAlgorithm = mappingAlgorithm,
        activeBlockCount = activeBlockCount,
        drive = drive,
        partition = partition,
        sectorOffset = off,
        maximumBlockCount = partition.byteSize / sectorSize,
        cache = {},
        cacheCap = math.floor(MAX_CACHE_SIZE / sectorSize),
        sectorSize = sectorSize,
    }, lightfs)
end

---@param partition KOCOS.Partition
---@param format "lightfs"
function lightfs.format(partition, format)
    local drive = KOCOS.vdrive.proxy(partition.drive) or partition.drive
    if drive.type ~= "drive" then return false end
    if format ~= "lightfs" then return false end

    local sectorSize = drive.getSectorSize()
    local rootSector = HEADER

    rootSector = rootSector .. lightfs.encodeLE(1, 3) -- nextFreeBlock
    rootSector = rootSector .. lightfs.encodeLE(0, 3) -- rootSector
    rootSector = rootSector .. lightfs.encodeLE(0, 3) -- firstFreeSector
    rootSector = rootSector .. lightfs.encodeLE(0, 1) -- mappingAlgorithm
    rootSector = rootSector .. lightfs.encodeLE(1, 3) -- activeBlockCount (1 for root)

    rootSector = string.rightpad(rootSector, sectorSize)
    drive.writeSector(1 + partition.startByte / sectorSize, rootSector)

    return true
end

function lightfs:saveState()
    local rootSector = HEADER

    rootSector = rootSector .. lightfs.encodeLE(self.nextFreeBlock, 3)
    rootSector = rootSector .. lightfs.encodeLE(self.rootSector, 3)
    rootSector = rootSector .. lightfs.encodeLE(self.firstFreeSector, 3)
    rootSector = rootSector .. lightfs.encodeLE(self.mappingAlgorithm, 1)
    rootSector = rootSector .. lightfs.encodeLE(self.activeBlockCount, 3)

    self:writeSector(0, rootSector)
end

---@param s string
---@param start? integer
---@param len? integer
---@return integer
function lightfs.decodeLE(s, start, len)
    start = start or 0
    len = len or #s
    local n = 0
    local m = 1
    for i=1+start, start + len do
        n = n + m * s:byte(i, i)
    end
    return n
end

---@param x integer
---@param len integer
function lightfs.encodeLE(x, len)
    local s = ""
    while x > 0 do
        local b = x % 256
        s = s .. string.char(b)
        x = math.floor(x / 256)
    end
    while #s < len do
        s = s .. string.char(0)
    end
    return s
end

---@param sector integer
---@return string
function lightfs:readSector(sector)
    for i=1, #self.cache do
        if self.cache[i].sector == sector then
            return self.cache[i].data
        end
    end

    local data = self.drive.readSector(1 + self.sectorOffset + sector)

    table.insert(self.cache, {
        sector = sector,
        data = data,
    })
    while #self.cache > self.cacheCap do
        table.remove(self.cache, 1)
    end
    return data
end

---@param sector integer
---@param data string
function lightfs:writeSector(sector, data)
    for i=1, #self.cache do
        if self.cache[i].sector == sector then
            self.cache[i].data = data
        end
    end

    self.drive.writeSector(1 + self.sectorOffset + sector, data)
end

function lightfs:blockToSector(block)
    if self.mappingAlgorithm == 0 then
        return block
    else
        error("invalid mapping algorithm")
    end
end

---@param data string
---@param i integer
function lightfs:decodeDirEntry(data, i)
    local name = data:sub(i + 1, i + 32):gsub("\0", "")
    local mtimeMS = self.decodeLE(data, i + 32, 8)
    local permissions = self.decodeLE(data, i + 40, 2)
    local ftype = self.decodeLE(data, i + 42, 1)
    local firstBlockListSector = self.decodeLE(data, i + 43, 3)
    local fileSize = self.decodeLE(data, i + 46, 4)
    local blockCount = self.decodeLE(data, i + 50, 3)

    ---@type KOCOS.LightFS.DirEntry
    return {
        name = name,
        mtimeMS = mtimeMS,
        permissions = permissions,
        ftype = ftype,
        firstBlockListSector = firstBlockListSector,
        fileSize = fileSize,
        blockCount = blockCount,
    }
end

---@param dirEntry KOCOS.LightFS.DirEntry
---@return string
function lightfs:encodeDirEntry(dirEntry)
    local s = string.rightpad(dirEntry.name, 32)
    .. self.encodeLE(dirEntry.mtimeMS, 8)
    .. self.encodeLE(dirEntry.permissions, 2)
    .. self.encodeLE(dirEntry.ftype, 1)
    .. self.encodeLE(dirEntry.firstBlockListSector, 3)
    .. self.encodeLE(dirEntry.fileSize, 4)
    .. self.encodeLE(dirEntry.blockCount, 3)

    return string.rightpad(s, DIRENT_SIZE)
end

function lightfs:spaceUsed()
    return self.activeBlockCount * self.sectorSize
end

function lightfs:spaceTotal()
    return self.partition.byteSize
end

KOCOS.fs.addDriver(lightfs)

KOCOS.test("LightFS Driver", function()
    local drive = KOCOS.testing.drive(512, 256 * 1024, "lightfs test")

    local partition = assert(KOCOS.fs.wholeDrivePartition(drive), "partition system broken")

    KOCOS.fs.format(partition, "lightfs")
end)

KOCOS.log("LightFS driver loaded")
