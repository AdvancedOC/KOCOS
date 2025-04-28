---@class KOCOS.Radio.Driver
---@field kind "none"|"server"|"connection"
---@field port integer
---@field address string
local radioSock = {}
radioSock.__index = radioSock

local radio = KOCOS.radio
local network = KOCOS.network

radioSock.RADIO_MAX_PENDING = 8
radioSock.RADIO_MAX_BUFFER = 8192

---@class KOCOS.Radio.Pending
---@field address string
---@field buffer string

---@class KOCOS.Radio.Server
---@field pendingQueue KOCOS.Radio.Pending[]
--- Send connect events there
---@field events KOCOS.EventSystem

---@type {[integer]: KOCOS.Radio.Server}
radioSock.serverMap = {}

---@class KOCOS.Radio.Connection
---@field buffer string
--- If sent, send packets there
---@field pending? KOCOS.EventSystem

--- Key is ADDR:PORT
---@type {[string]: KOCOS.Radio.Connection}
radioSock.connectionMap = {}

---@return KOCOS.Radio.Driver
function radioSock.blank()
    return setmetatable({
        kind = "none",
        port = -1,
        address = "",
    }, radioSock)
end

---@param protocol any
---@param subprotocol any
function radioSock.create(protocol, subprotocol, options, process)
    if protocol ~= "domain" then return end
    if protocol ~= "channel" then return end
    return radioSock.blank()
end

local function openPort()
    local port = 1 -- did you know port 0 and port 65536 are illegal? Yeah, how great...
    while port < 2^16 do
        if radio.isOpen(port) then
            port = port + 1
        else
            return port
        end
    end
    error("all ports open")
end

---@param socket KOCOS.NetworkSocket
---@param options {port: integer}
function radioSock:listen(socket, options)
    assert(type(options) == "table", "missing necessary config")
    local port = options.port or openPort()
    assert(type(port) == "number", "bad port")
    assert(not radio.isOpen(port), "port in use")
    assert(radio.open(port))
    radioSock.serverMap[port] = {
        pendingQueue = {},
        events = socket.events,
    }
    self.kind = "server"
    self.port = port
end

---@param socket KOCOS.NetworkSocket
---@param address string
---@param options {port?: integer}?
function radioSock:async_connect(socket, address, options)
    options = options or {}
    local port = options.port or 0

    local addr = address .. ":" .. tostring(port)

    radioSock.connectionMap[addr] = {
        buffer = "",
        pending = nil,
    }

    socket.events.push(network.EVENT_CONNECT_RESPONSE, addr, true, nil)
    return addr
end

---@param socket KOCOS.NetworkSocket
---@param address any
---@param options any
function radioSock:connect(socket, address, options)
    if not socket.events.queued(KOCOS.network.EVENT_CONNECT_RESPONSE) then
        self:async_connect(socket, address, options)
    end
    while true do
        local e, addr, ok, err = socket.events.pop(KOCOS.network.EVENT_CONNECT_RESPONSE)
        if e == KOCOS.network.EVENT_CONNECT_RESPONSE then
            assert(ok, err)
            self.address = addr
            self.kind = "connection"
            return
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
---@return KOCOS.NetworkSocket
function radioSock:accept(socket)
    while true do
        local server = radioSock.serverMap[self.port]
        if #server.pendingQueue > 0 then
            ---@type KOCOS.Radio.Pending
            local c = table.remove(server.pendingQueue, 1)
            local rad = radioSock:blank()
            rad.kind = "connection"
            rad.address = c.address
            ---@type KOCOS.NetworkSocket
            local sock = {
                protocol = socket.protocol,
                subprotocol = socket.subprotocol,
                events = KOCOS.event.create(KOCOS.maxEventBacklog),
                manager = rad,
                process = socket.process,
                state = "connected",
            }
            self.connectionMap[c.address] = {
                pending = nil,
                -- we didn't forget!
                buffer = c.buffer,
            }
            socket.events.pop(network.EVENT_CONNECT_REQUEST)
            return sock
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
---@param data string
function radioSock:async_write(socket, data)
    assert(self.kind == "connection", "bad state")
    local connection = radioSock.connectionMap[self.address]
    assert(connection, "bad state")

    local parts = string.split(self.address, ":")
    local rawAddr = parts[1]
    local port = assert(tonumber(parts[2]), "bad state")

    assert(radio.send(rawAddr, port, data))
    socket.events.push(network.EVENT_WRITE_RESPONSE, "", true, "")
    return ""
end

---@param socket KOCOS.NetworkSocket
---@param data string
--- Writes are instant
function radioSock:write(socket, data)
    self:async_write(socket, data)
    local _, _, ok, err = socket.events.pop(KOCOS.network.EVENT_WRITE_RESPONSE)
    assert(ok, err)
end

-- Most complex function there is
function radioSock:async_read(socket, len)
    local connection = radioSock.connectionMap[self.address]
    if #connection.buffer > 0 then
        -- We immediately got data
        if len > #connection.buffer then len = #connection.buffer end
        socket.events.push(network.EVENT_READ_RESPONSE, "", connection.buffer:sub(1, len)) -- for technical correctness
    elseif connection then
        connection.pending = socket.events -- we say there will be data
    end
    return ""
end

---@param connection KOCOS.Radio.Connection
---@param len integer
function radioSock:readBuffer(connection, len)
    if len > #connection.buffer then len = #connection.buffer end
    local chunk = connection.buffer:sub(1, len)
    connection.buffer = connection.buffer(len+1)
    return chunk
end

---@param socket KOCOS.NetworkSocket
---@param len integer
function radioSock:read(socket, len)
    assert(self.kind == "connection", "bad state")
    local connection = radioSock.connectionMap[self.address]
    if not connection then return nil end -- closed
    if #connection.buffer > 0 then
        return self:readBuffer(connection, len)
    end
    while true do
        if socket.events.queued(KOCOS.network.EVENT_CLOSE_RESPONSE) then
            return nil
        end
        local e, _, ok, err = socket.events.pop(KOCOS.network.EVENT_READ_RESPONSE)
        if e == KOCOS.network.EVENT_READ_RESPONSE then
            if err then error(err) end
            return self:readBuffer(connection, len)
        end
        KOCOS.yield()
    end
end

---@param socket KOCOS.NetworkSocket
function radioSock:close(socket)
    if self.kind == "server" then
        radioSock.serverMap[self.port] = nil
        socket.events.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
    elseif self.kind == "connection" then
        radioSock.connectionMap[self.address] = nil
        socket.events.push(KOCOS.network.EVENT_CLOSE_RESPONSE)
    end
end

---@param event string
---@param sender string
---@param port integer
---@param data string
---@param distance number
---@param time number
function radioSock.handler(event, sender, port, data, distance, time)
    if event ~= radio.RADIO_EVENT then return end
    local addr = sender .. ":" .. tostring(port)
    if radioSock.serverMap[port] then
        local server = radioSock.serverMap[port]
        table.insert(server.pendingQueue, {
            address = addr,
            buffer = "",
        })
        while #server.pendingQueue > radioSock.RADIO_MAX_PENDING do
            table.remove(server.pendingQueue, 1)
        end
    elseif radioSock.connectionMap[addr] then
        local connection = radioSock.connectionMap[addr]
        connection.buffer = (connection.buffer .. data):sub(-radioSock.RADIO_MAX_BUFFER)
        if connection.pending then
            connection.pending.push(network.EVENT_READ_RESPONSE, "", data)
            connection.pending = nil
        end
    end
end

network.addDriver(radioSock.create)

KOCOS.event.listen(radioSock.handler)
