-- Minitel Partition Table
-- A very basic partition table format, with basic features
-- https://git.shadowkat.net/izaya/OC-misc/src/branch/master/partition

---@param data string
local function readBigEndian(data)
    local n = 0
    for i = 1, #data do
        n = n * 256
        n = n + data:byte(i, i)
    end
    return n
end

---@param address string
---@param i integer
---@return string
local function computeUUID(address, i)
    math.randomseed(readBigEndian(address:sub(1, 3)) * i)
    return KOCOS.testing.uuid()
end

---@param drive table
---@param data string
---@param i integer
---@return KOCOS.Partition
local function parsePartitionStruct(drive, data, i)
    local sectorSize = drive.getSectorSize()

    local name = data:sub(1, 20)
    local terminator = string.find(name, "\0")
    if terminator then
        name = name:sub(1, terminator-1)
    end

    local rawType = data:sub(21, 24)

    local kind = "user"
    if rawType == "kcos" then
        kind = "root"
    elseif rawType == "boot" then
        kind = "boot"
    elseif rawType == "back" then
        kind = "reserved"
    end

    local startSector = readBigEndian(data:sub(25, 28))
    local sectorLength = readBigEndian(data:sub(29, 32))

    ---@type KOCOS.Partition
    return {
        drive = drive,
        name = name,
        kind = kind,
        storedKind = rawType,
        readonly = false, -- no support for readonly partitions.
        startByte = (startSector - 1) * sectorSize, -- KOCOS partitions officially start at 0
        byteSize = sectorLength * sectorSize,
        -- worst algorithm for UUIDs ever
        uuid = computeUUID(drive.address, i),
    }
end

---@type KOCOS.PartitionParser
function KOCOS.mtpt(drive)
    drive = KOCOS.vdrive.proxy(drive) or drive
    if drive.type ~= "drive" then return end

    local lastSector = math.floor(drive.getCapacity() / drive.getSectorSize())

    ---@type string
    local partitionData = drive.readSector(lastSector)

    if partitionData:sub(21, 24) ~= "mtpt" then return end -- didnt pass header check

    ---@type KOCOS.Partition[]
    local partitions = {}

    for i=1, #partitionData, 32 do
        local part = parsePartitionStruct(drive, partitionData:sub(i, i+31), math.floor(i / 32))
        if part.name ~= "" then
            table.insert(partitions, part)
        end
    end

    return partitions, "mtpt"
end

KOCOS.fs.addPartitionParser(KOCOS.mtpt)
