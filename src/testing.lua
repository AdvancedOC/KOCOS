local testing = {}

function testing.uuid()
    local hexDigits = "0123456789ABCDEF"
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
    local buffer = string.rep("\0", capacity) -- we love eating RAM
    local invalidSector = math.floor(capacity / sectorSize)

    return {
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
        readByte = function(off)
            assert(math.floor(off) == off, "DRIVE: byte offset is not integer")
            if off < 0 or off >= #buffer then
                error("DRIVE: out of bounds")
            end
            return buffer:byte(off+1, off+1)
        end,
        writeByte = function(off, value)
            assert(math.floor(off) == off, "DRIVE: byte offset is not integer")
            if off < 0 or off >= #buffer then
                error("DRIVE: out of bounds")
            end
            assert(math.floor(value) == value, "DRIVE: byte is not integer")
            assert(value >= 0 and value < 256, "DRIVE: invalid byte")
            local pre = buffer:sub(1, off)
            local post = buffer:sub(off+2)
            buffer = pre .. string.char(value) .. post
            return true
        end,
        readSector = function(sector)
            assert(math.floor(sector) == sector, "DRIVE: sector is not integer")
            assert(sector >= 0 and sector < invalidSector, "DRIVE: sector out of bounds")
            return buffer:sub(sector * sectorSize + 1, (sector + 1) * sectorSize)
        end,
        writeSector = function(sector, value)
            assert(math.floor(sector) == sector, "DRIVE: sector is not integer")
            assert(sector >= 0 and sector < invalidSector, "DRIVE: sector out of bounds")
            assert(#value == sectorSize, "DRIVE: sector value is not correct")
            local pre = buffer:sub(1, sector * sectorSize)
            local post = buffer:sub((sector + 1) * sectorSize + 1)
            buffer = pre .. value .. post
            return true
        end,
        getCapacity = function()
            return capacity
        end,
    }
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
                testing.expectFail(drive.writeByte, 0, 256)
                testing.expectFail(drive.writeSector, 2^32, string.rep(" ", sectorSize))
                testing.expectFail(drive.writeSector, 0, string.rep(" ", sectorSize-1))
                for _=1,32 do
                    local randomByte = math.random(0, 255)
                    local randomPos = math.random(0, capacity-1)
                    assert(drive.writeByte(randomPos, randomByte))
                    assert(drive.readByte(randomPos) == randomByte)
                end

                for i=0,sectorCount-1 do
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
                    assert(drive.writeSector(i-1, data))
                end
                for j=1,sectorCount do
                    local i = sectorIdx[j]
                    assert(drive.readSector(i-1) == sectors[i], "bad storage")
                end
            end)
        end
    end
end
