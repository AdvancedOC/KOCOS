-- Little endian my beloved
local function readNum(drive, pos, size)
    local n = 0
    local m = 1

    for i=1,size do
        local byte = drive.readByte(pos+i-1)
        n = n + byte * m
        m = m * 256
    end
    return n
end

local function readBinary(drive, pos, size)
    local s = ""

    for i=1,size do
        local b = drive.readByte(pos+i-1)
        if b < 0 then b = b + 256 end
        s = s .. string.char(b)
    end

    return s
end

local function readGUID(drive, pos)
    local bin = readBinary(drive, pos, 16)
    if bin == string.rep("\0", 16) then return nil end
    local partA = bin:sub(1, 4)
    local partB = bin:sub(5, 6)
    local partC = bin:sub(7, 8)
    bin = partA:reverse() .. partB:reverse() .. partC:reverse() .. bin:sub(9)
    local digits4 = "0123456789ABCDEF"

    local base16d = ""
    for i=1,16 do
        local byte = string.byte(bin, i, i)
        local upper = math.floor(byte / 16) + 1
        local lower = byte % 16 + 1
        base16d = base16d .. digits4:sub(upper, upper) .. digits4:sub(lower, lower)
    end

    local guid = base16d:sub(1, 8) .. "-"
        .. base16d:sub(9, 12) .. "-"
        .. base16d:sub(13, 16) .. "-"
        .. base16d:sub(17, 20) .. "-"
        .. base16d:sub(21)

    return guid
end

local function align(pos, blockSize)
    local remaining = blockSize - pos % blockSize
    if remaining == blockSize then return pos end
    return pos + remaining
end

---@type KOCOS.PartitionParser
function KOCOS.gpt(drive)
    drive = KOCOS.vdrive.proxy(drive) or drive
    if drive.type ~= "drive" then return end
    -- This is currently NOT OPTIMIZED AT ALL
    local blockSize = drive.getSectorSize()

    local off = blockSize+1 -- skip LBA 0 since we don't care about MBR

    -- Check if GPT drive

    local sig = readBinary(drive, off, 8)
    if sig ~= "EFI PART" then return end -- not GPT drive.

    -- Revision number and CRC32 checksums are skipped, not needed
    local startOfPartitionsLBA = readNum(drive, off + 72, 8)
    local partitionCount = readNum(drive, off + 80, 4)
    local partitionEntrySize = readNum(drive, off + 84, 4)

    off = startOfPartitionsLBA * blockSize

    local visited = {}
    local partitions = {}

    for i=1, partitionCount do
        local typeGUID = readGUID(drive, off)
        if typeGUID then
            local partGUID = readGUID(drive, off+16)
            if partGUID == nil then return end
            if not visited[partGUID] then
                local startLBA = readNum(drive, off+32, 8)
                local endLBA = readNum(drive, off+40, 8)
                local attrs = readNum(drive, off+48, 8)
                local name = ""

                for i=1,36 do
                    local byte = readNum(drive, off+56+(i-1)*2, 1)
                    if byte == 0 then break end -- null termination ftw
                    name = name .. string.char(byte) -- fuck your safety
                end

                local kind = "user"
                if typeGUID == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B" then -- actually EFI BOOT
                    kind = "boot"
                elseif typeGUID == "4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709" then -- actually Linux amd64 root
                    kind = "root"
                elseif typeGUID == "9E1A2D38-C612-4316-AA26-8B49521E5A8B" then -- actually PReP boot
                    kind = "reserved"
                end

                local readonly = bit32.btest(attrs, (2^59))

                ---@type KOCOS.Partition
                local part = {
                    ---@diagnostic disable-next-line
                    uuid = partGUID,
                    name = name,
                    startByte = startLBA * blockSize,
                    byteSize = (endLBA - startLBA + 1) * blockSize,
                    ---@diagnostic disable-next-line
                    storedKind = typeGUID,
                    kind = kind,
                    readonly = readonly,
                    drive = drive,
                }

                table.insert(partitions, part)
            end
            visited[partGUID] = true
            off = off + partitionEntrySize
        end
    end

    return partitions, "gpt"
end

KOCOS.fs.addPartitionParser(KOCOS.gpt)

KOCOS.log("GPT driver loaded")
