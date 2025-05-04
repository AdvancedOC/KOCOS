-- Ripped straight from UlOS 2
-- https://github.com/oc-ulos/oc-cynosure-2/blob/dev/src/fs/partition/osdi.lua
local magic = "OSDI\xAA\xAA\x55\x55"
local pack_format = "<I4I4c8I3c13" -- this is actually *wrong* in the OSDI driver of Cynosure-2, c3 instead of I3, meaning the flags were read as string

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

---@type KOCOS.PartitionParser
function KOCOS.osdi(drive)
    drive = KOCOS.vdrive.proxy(drive) or drive
    if drive.type ~= "drive" then return end
    local sector = drive.readSector(1)
    local sectorSize = #sector
    local headerParts = {string.unpack(pack_format, sector)}

    if headerParts[1] ~= 1 or headerParts[2] ~= 0 or headerParts[3] ~= magic then return end

    ---@type KOCOS.Partition[]
    local parts = {}

    repeat
        sector = sector:sub(33)

        ---@type integer, integer, string, integer, string
        local start, size, partType, partFlags, partName = string.unpack(pack_format, sector)

        partType = partType:gsub("\0", "")
        partName = partName:gsub("\0", "")

        -- TODO: figure out how tf reserved works in this
        local kocosPartType = "user"
        if bit32.btest(partFlags, 512) then
            kocosPartType = "boot"
        elseif partType == "kocos" then
            kocosPartType = "root"
        end

        local uuid = computeUUID(drive.address, #parts+1)

        if #partName > 0 then
            parts[#parts+1] = {
                drive = drive,
                uuid = uuid,
                kind = kocosPartType,
                storedKind = partType,
                name = partName,
                startByte = (start - 1) * sectorSize,
                byteSize = size * sectorSize,
                readonly = false,
            }
        end
    until #sector <= 32

    return parts, "osdi"
end

KOCOS.fs.addPartitionParser(KOCOS.osdi)
