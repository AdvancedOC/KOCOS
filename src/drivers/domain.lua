-- Domain sockets

---@class KOCOS.Domain.Connection
---@field id integer
---@field serverEvents KOCOS.EventSystem
---@field clientEvents KOCOS.EventSystem

---@class KOCOS.Domain.Server
---@field connections {[integer]: KOCOS.Domain.Connection}
---@field pending KOCOS.Domain.Connection[]
---@field maxPending integer
---@field globalServerEvents KOCOS.EventSystem
---@field nextConnection integer

---@type {[any]: KOCOS.Domain.Server}
local servers = {}

---@class KOCOS.Domain.Driver
---@field kind "none"|"server"|"client"|"serverConnection"
---@field address string
---@field id integer
---@field server string
local domain = {}
domain.__index = domain

---@return KOCOS.Domain.Driver
function domain.blank()
    return setmetatable({
        kind = "none",
        address = "",
        id = 0,
        server = "",
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

---@param socket KOCOS.NetworkSocket
---@param options {port: any, maxPending: integer?}
function domain:listen(socket, options)
    assert(type(options) == "table", "missing necessary config")
    local port = options.port
    local maxPending = options.maxPending or 128
    assert(type(maxPending) == "number", "bad maxPending")
    assert(not servers[port], "port already in use")
    self.server = port
    servers[port] = {
        connections = {},
        pending = {},
        maxPending = maxPending,
        globalServerEvents = socket.events,
        nextConnection = 0,
    }
end

---@param socket KOCOS.NetworkSocket
---@param address any
function domain:async_connect(socket, address, options)
    local server = servers[address]
    assert(server, "no domain server")
    self.server = address
    table.insert(server.pending, {
        id = 0,
        serverEvents = KOCOS.event.create(KOCOS.maxEventBacklog),
        clientEvents = socket.events,
    })
    server.globalServerEvents.push(KOCOS.network.EVENT_CONNECT_REQUEST)
    while #server.pending > server.maxPending do
        ---@type KOCOS.Domain.Connection
        local c = table.remove(server.pending, 1)
        c.clientEvents.push(KOCOS.network.EVENT_CONNECT_RESPONSE, 0, false, "timed out")
    end
    return ""
end

---@param socket KOCOS.NetworkSocket
---@param address any
---@param options any
function domain:connect(socket, address, options)
    if not socket.events.queued(KOCOS.network.EVENT_CONNECT_RESPONSE) then
        self:async_connect(socket, address, options)
    end
    while true do
        local e, id, ok, err = socket.events.pop(KOCOS.network.EVENT_CONNECT_RESPONSE)
        if e == KOCOS.network.EVENT_CONNECT_RESPONSE then
            assert(ok, err)
            self.id = id
            self.kind = "client"
            return
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
---@return KOCOS.NetworkSocket
function domain:accept(socket)
    while true do
        local server = servers[self.server]
        if #server.pending > 0 then
            ---@type KOCOS.Domain.Connection
            local c = table.remove(server.pending, 1)
            socket.events.pop(KOCOS.network.EVENT_CONNECT_REQUEST)
            local id = server.nextConnection
            server.nextConnection = id + 1
            local dom = domain.blank()
            dom.kind = "serverConnection"
            dom.id = id
            dom.server = self.server
            c.id = id
            server.connections[id] = c
            ---@type KOCOS.NetworkSocket
            local sock = {
                protocol = socket.protocol,
                subprotocol = socket.subprotocol,
                state = "connected",
                manager = dom,
                process = socket.process,
                events = c.serverEvents,
            }
            c.clientEvents.push(KOCOS.network.EVENT_CONNECT_RESPONSE, c.id, true)
            return sock
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
---@param data string
function domain:async_write(socket, data)
    local server = servers[self.server]
    if not server then
        socket.events.push(KOCOS.network.EVENT_WRITE_RESPONSE, "", false, "connection closed")
        return ""
    end
    local conn = server.connections[self.id]
    if not conn then
        socket.events.push(KOCOS.network.EVENT_WRITE_RESPONSE, "", false, "connection closed")
        return ""
    end
    if self.kind == "client" then
        -- Tell server we wrote data
        conn.serverEvents.push(KOCOS.network.EVENT_READ_RESPONSE, "", data)
    else
        -- Tell client we wrote data
        conn.clientEvents.push(KOCOS.network.EVENT_READ_RESPONSE, "", data)
    end
    socket.events.push(KOCOS.network.EVENT_WRITE_RESPONSE, "", true)
    KOCOS.yield()
    return ""
end

---@param socket KOCOS.NetworkSocket
---@param data string
--- Writes are instant
function domain:write(socket, data)
    self:async_write(socket, data)
    local _, _, ok, err = socket.events.pop(KOCOS.network.EVENT_WRITE_RESPONSE)
    assert(ok, err)
end

-- Most complex function there is
function domain:async_read(socket, len)
    return ""
end

---@param socket KOCOS.NetworkSocket
---@param len integer
function domain:read(socket, len)
    while true do
        if socket.events.queued(KOCOS.network.EVENT_CLOSE_RESPONSE) then
            return nil
        end
        local e, _, data, err = socket.events.pop(KOCOS.network.EVENT_READ_RESPONSE)
        if e == KOCOS.network.EVENT_READ_RESPONSE then
            if err then error(err) end
            return data
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
function domain:close(socket)
    if self.kind == "server" then
        servers[self.server] = nil
    elseif self.kind == "client" then
        local server = servers[self.server]
        if not server then return end
        local conn = server.connections[self.id]
        if not conn then return end
        conn.serverEvents.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
        socket.events.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
        server.connections[self.id] = nil
    elseif self.kind == "serverConnection" then
        local server = servers[self.server]
        if not server then return end
        local conn = server.connections[self.id]
        if not conn then return end
        socket.events.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
        conn.clientEvents.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
        server.connections[self.id] = nil
    end
end

---@param socket KOCOS.NetworkSocket
function domain:ioctl(socket)
    error("unsupported")
end

KOCOS.network.addDriver(domain.create)

KOCOS.log("Domain socket driver loaded")
