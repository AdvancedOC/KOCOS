-- Internet network system

---@class KOCOS.InternetDriver
---@field internet table
---@field subprotocol "http"|"tcp"
---@field connection any
local internet = {}
internet.__index = internet

---@param protocol "internet"
---@param subprotocol "http"|"tcp"
---@param options any
---@param process KOCOS.Process
function internet.create(protocol, subprotocol, options, process)
    if protocol ~= "internet" then return end
    if subprotocol ~= "http" and subprotocol ~= "tcp" then return end
    local modem = component.internet
    if not modem then return nil, "offline" end
    if subprotocol == "tcp" and not modem.isTcpEnabled() then
        return nil, "disabled"
    end
    if subprotocol == "http" and not modem.isHttpEnabled() then
        return nil, "disabled"
    end
    ---@type KOCOS.InternetDriver
    local manager = setmetatable({
        internet = modem,
        subprotocol = subprotocol,
        connection = nil,
    }, internet)
    return manager
end

function internet:listen(socket, options)
    error("unsupported")
end

function internet:connect(socket, address, options)
    assert(type(address) == "string", "bad address")
    options = options or {}

    if self.subprotocol == "tcp" then
        self.connection = self.internet.connect(address, options.port)
    else
        self.connection = self.internet.request(address, options.postData, options.headers)
    end
    self.connection.finishConnect()
end

function internet:read(socket, len)
    return self.connection.read(len ~= math.huge and len or nil)
end

function internet:write(socket, data)
    if self.subprotocol == "http" then
        error("unsupported")
    end

    return self.connection.write(data)
end

function internet:ioctl(socket, action, ...)
    if self.subprotocol == "http" then
        if action == "response" then
            return self.connection.response()
        end
    end
    error("unsupported")
end

function internet:close(socket)
    if self.connection then
        self.connection.close()
    end
end

-- TODO: Async internet I/O

function internet:async_connect()
    error("unsupported")
end

function internet:async_write()
    error("unsupported")
end

function internet:async_read()
    error("unsupported")
end

KOCOS.network.addDriver(internet.create)
