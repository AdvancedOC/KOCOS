local router = {}

router.drivers = {}

router.events = KOCOS.event

router.EVENT_CONNECT = "router_connect"
router.EVENT_DISCONNECT = "router_disconnect"
router.EVENT_PACKET = "router_packet"

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
    router.events.push(router.EVENT_CONNECT, network.uuid)
end

---@param network KOCOS.Network
---@param protocol string
---@return boolean
function router.networkSupports(network, protocol)
    for i=1,#network.protocols do
        if network.protocols[i] == protocol then
            return true
        end
    end
    return false
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

---@param uuid string
function router.forget(uuid)
    if router.currentNetworkUuid() == uuid then
        router.disconnect()
    end
    router.networks[uuid] = nil
end

function router.disconnect()
    if router.isOnline() then
        router.events.push(router.EVENT_DISCONNECT, router.current.uuid)
        router.current.manager:disconnect(router.current)
    end
    router.current = nil
end

function router.send(packet)
    local current = assert(router.current, "offline")
    current.manager:send(current, packet)
end

function router.receivedPacket(packet)
    router.events.push(router.EVENT_PACKET, packet)
end

function router.update()
    for id, network in pairs(router.networks) do
        network.manager:update(network)
    end
end

KOCOS.router = router

KOCOS.runOnLoop(router.update)

KOCOS.log("Router subsystem loaded")
