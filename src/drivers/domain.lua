-- Domain sockets

---@class KOCOS.Domain.Connection
---@field id integer
---@field closed boolean
---@field serverEvents KOCOS.EventSystem
---@field clientEvents KOCOS.EventSystem

---@class KOCOS.Domain.Server
---@field connections {[integer]: KOCOS.Domain.Connection}
---@field pending KOCOS.Domain.Connection[]
---@field maxPending integer

---@class KOCOS.Domain.Driver
---@field kind "none"|"server"|"client"|"serverConnection"
---@field address string
---@field id integer
---@field outEvents? KOCOS.EventSystem
---@field server? KOCOS.Domain.Server
local domain = {}

---@return KOCOS.Domain.Driver
function domain.blank()
    return setmetatable({
        kind = "none",
        address = "",
        id = 0,
    }, domain)
end

---@param protocol "domain"
---@param subprotocol "channel"
---@param options any
---@param process KOCOS.Process
function domain.create(protocol, subprotocol, options, process)
    if protocol ~= "domain" then return end
    if subprotocol ~= "channel" then return end
    return domain.blank()
end

KOCOS.network.addDriver(domain.create)

KOCOS.log("Domain socket driver")
