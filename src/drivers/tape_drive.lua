-- Support for Computronics Tape Drive as a VDrive.
-- Don't ask, those things are super high capacity

---@type KOCOS.VDrive.Driver
local function tapeDriveProxy(proxy)
    if proxy.type ~= "tape_drive" then return end
    if not proxy.isReady() then return end

    local function seek(position)
        local cur = proxy.getPosition()
        proxy.seek(position - cur)
    end

    local sectorSize = 512

    ---@type KOCOS.VDrive
    return {
        type = "drive",
        slot = proxy.slot,
        address = proxy.address,
        getLabel = proxy.getLabel,
        setLabel = proxy.setLabel,
        getCapacity = proxy.getSize,
        getSectorSize = function() return sectorSize end,
        getPlatterCount = function() return 1 end,
        readByte = function(byte)
            seek(byte - 1)
            local b = proxy.read():byte()
            if b >= 128 then b = b - 256 end
            return b
        end,
        writeByte = function(byte, val)
            seek(byte - 1)
            proxy.write(val)
        end,
        readSector = function(sector)
            seek((sector - 1) * sectorSize)
            return proxy.read(sectorSize)
        end,
        writeSector = function(sector, value)
            seek((sector - 1) * sectorSize)
            proxy.write(value)
        end,
    }
end

KOCOS.vdrive.addDriver(tapeDriveProxy)
