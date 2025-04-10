local network = {}

network.drivers = {}

network.EVENT_READ_RESPONSE = "packet"
network.EVENT_WRITE_RESPONSE = "response"
network.EVENT_CONNECT_RESPONSE = "connect"

function network.addDriver(driver)
    table.insert(network.drivers, driver)
end

---@class KOCOS.NetworkSocket
---@field protocol string
---@field subprotocol string
---@field process KOCOS.Process
---@field events KOCOS.EventSystem
---@field state "connected"|"listening"|"none"
---@field manager table

---@param protocol string
---@param subprotocol string
---@param options any
---@param process KOCOS.Process
---@return KOCOS.NetworkSocket?, string
function network.newSocket(protocol, subprotocol, options, process)
    options = options or {}
    for i=#network.drivers,1,-1 do
        local driver = network.drivers[i]
        local manager, err = driver(protocol, subprotocol, options, process)
        -- err means accepted, but with an error
        if err then return nil, err end
        if manager then
            ---@type KOCOS.NetworkSocket
            local sock = {
                protocol = protocol,
                subprotocol = subprotocol,
                process = process,
                events = KOCOS.event.create(options.backlog or KOCOS.maxEventBacklog),
                state = "none",
                manager = manager,
            }
            return sock, ""
        end
    end
    return nil, "missing protocol"
end

---@param socket KOCOS.NetworkSocket
function network.listen(socket, options)
    if socket.state ~= "none" then
        error("bad state")
    end
    socket.manager:listen(socket, options)
    socket.state = "listening"
end

---@param socket KOCOS.NetworkSocket
function network.connect(socket, address, options)
    if socket.state ~= "none" then
        error("bad state")
    end
    socket.manager:connect(socket, address, options)
    socket.state = "connected"
end

---@param socket KOCOS.NetworkSocket
---@return string -- Packet ID
function network.async_connect(socket, address, options)
    if socket.state ~= "none" then
        error("bad state")
    end
    return socket.manager:async_connect(socket, address, options)
end

---@param socket KOCOS.NetworkSocket
---@param data string
---@return integer
-- Returns how many bytes were written
function network.write(socket, data)
    assert(socket.state == "connected", "not connected")
    return socket.manager:write(socket, data)
end

---@param socket KOCOS.NetworkSocket
---@param data string
---@return string
-- Returns packet ID
function network.async_write(socket, data)
    return socket.manager:async_write(socket, data)
end

---@param socket KOCOS.NetworkSocket
---@param len integer
---@return string?
function network.read(socket, len)
    assert(socket.state == "connected", "not connected")
    return socket.manager:read(socket, len)
end

---@param socket KOCOS.NetworkSocket
---@param len integer
---@return string
-- Returns packet ID
function network.async_read(socket, len)
    return socket.manager:async_read(socket, len)
end

---@param socket KOCOS.NetworkSocket
---@param action string
function network.ioctl(socket, action, ...)
    return socket.manager:ioctl(socket, action, ...)
end

---@param socket KOCOS.NetworkSocket
function network.close(socket)
    socket.manager:close(socket)
end

KOCOS.network = network

KOCOS.log("Network subsystem loaded")
