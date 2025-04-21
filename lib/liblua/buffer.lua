---@class buffer.stream 
---@field resource any
---@field read fun(resource: any, len: number): string?, string?
---@field write fun(resource: any, buffer: string): boolean, string
---@field seek fun(resource: any, whence: seekwhence, off: integer): integer, string
---@field ioctl fun(resource: any, action: string, ...): ...
---@field close fun(resource: any): boolean, string

---@class buffer
---@field stream buffer.stream
---@field mode "w"|"a"|"r"
---@field text boolean
---@field buffer string?
---@field buflen integer
local buffer = {}
buffer.__index = buffer

---@param stream buffer.stream
---@param mode "w"|"wb"|"r"|"rb"|"a"|"ab"
function buffer.wrap(stream, mode)
    return setmetatable({
        stream = stream,
        mode = mode:sub(1, 1),
        text = mode:sub(2) ~= "b",
        buffer = "",
        -- 16KiB buffer max
        buflen = 16*1024,
    }, buffer)
end

function buffer:flush()

end

function buffer:read(...)

end

function buffer:write(...)

end

---@param whence seekwhence
---@param off integer
function buffer:seek(whence, off)

end

function buffer:close()
    self.buffer = nil
    self.stream.close(self.stream.resource)
end

function buffer:ioctl(action, ...)
    return self.stream.ioctl(self.stream.resource, action, ...)
end

return buffer
