local testing = {}

function testing.uuid()
    local hexDigits = "0123456789abcdef"
    local rawHex = ""
    for _=1,32 do
        local i = math.random(1, #hexDigits)
        rawHex = rawHex .. hexDigits:sub(i, i)
    end
    return rawHex:sub(1, 8) .. '-'
        .. rawHex:sub(9, 12) .. '-'
        .. rawHex:sub(13, 16) .. '-'
        .. rawHex:sub(17, 20) .. '-'
        .. rawHex:sub(21, 32)
end

-- Creates a fake "drive" proxy with a random testing address
function testing.drive(sectorSize, capacity, name)
    name = name or ("TEST " .. testing.uuid())
    local invalidSector = math.floor(capacity / sectorSize) + 1

    local defaultSector = string.rep("\0", sectorSize)
    local sectors = {}

    local drive = {
        slot = -1,
        type = "drive",
        address = testing.uuid(),
        getLabel = function()
            return name
        end,
        setLabel = function()
            return name
        end,
        getPlatterCount = function()
            return 1
        end,
        getSectorSize = function()
            return sectorSize
        end,
        readSector = function(sector)
            assert(math.floor(sector) == sector, "DRIVE: sector is not integer")
            assert(sector > 0 and sector < invalidSector, "DRIVE: sector out of bounds")
            return sectors[sector] or defaultSector
        end,
        writeSector = function(sector, value)
            assert(math.floor(sector) == sector, "DRIVE: sector is not integer")
            assert(sector >= 0 and sector < invalidSector, "DRIVE: sector out of bounds")
            assert(#value == sectorSize, "DRIVE: sector value is not correct")
            sectors[sector] = value
            return true
        end,
        getCapacity = function()
            return capacity
        end,
    }
    local function sectorFromOff(off)
        local sec = off
        sec = sec - 1
        sec = sec / sectorSize
        sec = math.floor(sec)
        return sec + 1, off - sec * sectorSize
    end
    function drive.readByte(off)
        assert(math.floor(off) == off, "DRIVE: byte offset is not integer")
        if off < 1 or off > capacity then
            error("DRIVE: out of bounds")
        end
        local sector, idx = sectorFromOff(off)
        return drive.readSector(sector):byte(idx, idx)
    end
    function drive.writeByte(off, value)
        assert(math.floor(off) == off, "DRIVE: byte offset is not integer")
        if off < 1 or off > capacity then
            error("DRIVE: out of bounds")
        end
        assert(math.floor(value) == value, "DRIVE: byte is not integer")
        assert(value >= 0 and value < 256, "DRIVE: invalid byte")
        local sector, idx = sectorFromOff(off)
        local buffer = drive.readSector(sector)
        local pre = buffer:sub(1, idx-1)
        local post = buffer:sub(idx+1)
        buffer = pre .. string.char(value) .. post
        if #buffer ~= sectorSize then
            error(string.format("%d %d %d", sector, idx, off))
        end
        drive.writeSector(sector, buffer)
        return true
    end
    return drive
end

function testing.expectFail(f, ...)
    local ok = pcall(f, ...)
    assert(not ok, "operation should have failed")
end

---@generic T
---@param a T[]
---@param b T[]
function testing.expectSameSorted(a, b)
    assert(#a == #b, "mismatched lengths")
    table.sort(a)
    table.sort(b)
    for i=1,#a do
        assert(a[i] == b[i], "different data")
    end
end

local testCount = 0
local checkedCount = 0
function KOCOS.test(name, func)
    if not KOCOS.selfTest then return end
    testCount = testCount + 1
    KOCOS.defer(function()
        checkedCount = checkedCount + 1
        KOCOS.log("Testing %s [%d / %d]...", name, checkedCount, testCount)
        local ok, err = xpcall(func, debug.traceback)
        if ok then
            KOCOS.log("PASSED")
        else
            KOCOS.logPanic("FAILED: %s", err)
        end
    end, -1000 - testCount)
end

KOCOS.testing = testing

-- Testing our actual testing mechanism
KOCOS.test("self-tests", function()
    testing.expectFail(error, "can't fail")
end)

do
    -- Testing drive proxies
    local sectorSizes = {512, 1024, 2048}
    local sectorCounts = {1, 2, 4, 16}
    for _, sectorSize in ipairs(sectorSizes) do
        for _, sectorCount in ipairs(sectorCounts) do
            local capacity = sectorSize * sectorCount
            local name = string.format(
                "Drive proxy (%s, %s)",
                string.memformat(sectorSize),
                string.memformat(capacity)
            )
            KOCOS.test(name, function()
                local drive = testing.drive(sectorSize, capacity)
                assert(drive.getCapacity() == capacity)

                testing.expectFail(drive.writeByte, 2^32, 0)
                testing.expectFail(drive.writeByte, 1, 256)
                testing.expectFail(drive.writeSector, 2^32, string.rep(" ", sectorSize))
                testing.expectFail(drive.writeSector, 1, string.rep(" ", sectorSize-1))
                for _=1,32 do
                    local randomByte = math.random(0, 255)
                    local randomPos = math.random(1, capacity)
                    assert(drive.writeByte(randomPos, randomByte))
                    assert(drive.readByte(randomPos) == randomByte)
                end

                for i=1,sectorCount do
                    local data = ""
                    for _=1,sectorSize do
                        data = data .. string.char(math.random(0, 255))
                    end
                    assert(drive.writeSector(i,data))
                    assert(drive.readSector(i) == data)
                end

                local sectors = {}
                local sectorIdx = {}
                for i=1,sectorCount do
                    sectorIdx[i] = i
                end
                for i=1,#sectorIdx do
                    local j = math.random(i)
                    sectorIdx[i], sectorIdx[j] = sectorIdx[j], sectorIdx[i]
                end
                for j=1,sectorCount do
                    local i = sectorIdx[j]
                    local data = ""
                    for _=1,sectorSize do
                        data = data .. string.char(math.random(0, 255))
                    end
                    sectors[i] = data
                    assert(drive.writeSector(i, data))
                end
                for j=1,sectorCount do
                    local i = sectorIdx[j]
                    assert(drive.readSector(i) == sectors[i], "bad storage")
                end
            end)
        end
    end
end
