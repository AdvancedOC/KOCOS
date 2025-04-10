local router = {}

router.drivers = {}

---@class KOCOS.Network
---@field uuid string
---@field protocols string[]
---@field auth "none"|"password"|string
---@field manager table

---@type {[string]: KOCOS.Network}
router.networks = {}

---@type KOCOS.Network?
router.current = nil

---@type KOCOS.Network?
router.connectingTo = nil

function router.addDriver(driver)
    table.insert(router.drivers, driver)
end

---@return KOCOS.Network?
function router.networkFromUuid(uuid)
    return router.networks[uuid]
end

---@param network KOCOS.Network
function router.connectTo(network)
    router.connectingTo = network
end

---@param network? KOCOS.Network
function router.isConnectingTo(network)
    if not router.connectingTo then return end
    if not network then return router.connectingTo ~= nil end
    return router.connectingTo.uuid == network.uuid
end

---@return string?
function router.currentNetworkUuid()
    if router.current then return router.current.uuid end
end

function router.isOnline()
    return router.current ~= nil
end

function router.isOffline()
    return router.current == nil
end

---@param network KOCOS.Network
function router.addNetwork(network)
    router.networks[network.uuid] = network
end

function router.forget(uuid)
    router.networks[uuid] = nil
end

function router.send(protocol, packet)
    local current = assert(router.current, "offline")
    current.manager:send(current, protocol, packet)
end

function router.update()
    for id, network in pairs(router.networks) do
        network.manager:update(network)
    end
end

KOCOS.router = router

KOCOS.runOnLoop(router.update)
