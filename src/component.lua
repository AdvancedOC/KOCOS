setmetatable(component, {
    __index = function(_, key)
        local primary = component.list(key)()
        if not primary then return nil end
        -- TODO: cache primaries
        return component.proxy(primary)
    end,
})

local addrRings = {}
local typeRings = {}

function component.setRingForAddress(address, ring)
    addrRings[address] = ring
end

function component.setRingForType(type, ring)
    typeRings[type] = ring
end

---@param address string
---@return integer
function component.ringFor(address)
    if addrRings[address] then return addrRings[address] end
    local t = component.type(address)
    if typeRings[t] then return typeRings[t] end
    return math.huge
end

component.setRingForType("gpu", 1)
component.setRingForType("screen", 1)
component.setRingForType("filesystem", 1)
component.setRingForType("drive", 1)
component.setRingForType("computer", 1)
component.setRingForType("eeprom", 0)

KOCOS.log("Component subsystem loaded")
