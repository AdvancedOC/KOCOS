-- KOCOS Partition Record
-- "There's a better way to partition"

--[[
// Big endian encoding
// Sectors start at 0 to use the 0-value of the numbers
// Sector size long.
struct header {
    char header[8] = "KPVv1.0\0"; // header string. 1 char = 1 byte, just like in Lua.
    uint8_t partitionCount;
    uint24_t partitionArray; // last sector for no partition array, stores where extra partitions are if the amount of partitions didn't fit here.
                            // Its capacity shall be assumed to be the largest amount of free space starting there.
                            // IT IS NOT ALLOWED TO POINT INSIDE OF A PARTITION. If it does, the behavior is implementation-defined.
    uint8_t reserved[116]; // first 128 bytes are for data. The padding is reserved and should be filled with 0s.
    struct partition array[]; // primary partition array, stored inside this sector to minimize waste.
};

enum flags {
    READONLY = 1, // this partition should not have its contents modified
    HIDDEN = 2, // this partition may be unimportant to the user, or for internal use only, and thus should be hidden.
    PINNED = 4, // this partition should not be relocated, as something needs it to be there. Typically used for "RESERVED"-type partitions.
};

// 64 bytes long.
struct partition {
    char name[32]; // padded with NULLs. Empty names should be ignored.
    uint24_t start; // first sector
    uint24_t len; // length of partition, in sectors.
    uint16_t flags; // see flags. All bits not specified in flags should be set to 0.
    char type[8]; // 8-byte type. Can be treated as a uint64_t or just a string. "BOOT-LDR" is reserved for the bootloader, "@GENERIC" is reserved for
                // generic user partitions, and "RESERVED" is reserved for partitions storing copies of files (sometimes used for boot records).
                // OSs should use them to annotate special functions, NOT FILESYSTEM TYPE.
    uint8_t uuid[16]; // Bytes are in the order seen in the stringified version.
};
]]

-- Name, start, len, flags, type, uuid
local partitionFormat = "c32>I3>I3>I2c8c16"

---@param drive KOCOS.VDrive
---@param data string
local function parsePartition(drive, data)
    ---@type string, integer, integer, integer, string, string
    local name, start, len, flags, partType, uuidBin = string.unpack(partitionFormat, data)

    local kind = "user"
    if kind == "BOOT-LDR" then
        kind = "boot"
    elseif kind == "@GENERIC" then
        kind = "user"
    elseif kind == "RESERVED" then
        kind = "reserved"
    elseif kind == "KCOSROOT" then
        kind = "root"
    end

    ---@type KOCOS.Partition
    return {
        name = name:gsub('\0', ''),
        uuid = BinToUUID_direct(uuidBin),
        drive = drive,
        startByte = start * drive.getSectorSize(),
        byteSize = len * drive.getSectorSize(),
        kind = kind,
        readonly = flags % 2 == 1,
        storedKind = partType,
    }
end

---@type KOCOS.PartitionParser
function KOCOS.kpr(drive)
    drive = KOCOS.vdrive.proxy(drive) or drive
    if not drive then return end
    if drive.type ~= "drive" then return end

    local lastSector = drive.getCapacity() / drive.getSectorSize()

    local partTable = drive.readSector(lastSector)

    if partTable:sub(1, 8) ~= "KPRv1.0\0" then return end
    local partCount = partTable:byte(9, 9)
    local partArr = string.unpack(">I3", partTable, 10)
    if partArr ~= lastSector then return end -- we do not support extra partition array rn lol

    -- first 128 bytes are not partitions. There is a lot of reserved space
    local allPartData = partTable:sub(129)

    local partitions = {}

    for i=0, partCount-1 do
        local part = parsePartition(drive, allPartData:sub(i*64 + 1, i*64 + 64))
        if part.name ~= "" then
            table.insert(partitions, part)
        end
    end

    return partitions, "kpr"
end

KOCOS.fs.addPartitionParser(KOCOS.kpr)
