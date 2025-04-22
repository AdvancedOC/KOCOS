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
---@field buffering "no"|"line"|"full"
---@field buflen integer
---@field closed boolean
local buffer = {}
buffer.__index = buffer

---@param stream buffer.stream
---@param mode "w"|"wb"|"r"|"rb"|"a"|"ab"
function buffer.wrap(stream, mode)
    return setmetatable({
        stream = stream,
        mode = mode:sub(1, 1),
        text = mode:sub(2) ~= "b",
        buffering = "line",
        buffer = "",
        -- 16KiB buffer max
        buflen = 16*1024,
        closed = false,
    }, buffer)
end

function buffer:unwrap()
    return self.stream.resource
end

function buffer:setvbuf(buffering, size)
    assert(buffering == "no" or buffering == "line" or buffering == "full", "bad mode")
    size = size or self.buflen
    assert(type(size) == "number", "bad size")
    local ok, err = self:flush()
    if ok then
        self.buffering = buffering
        self.size = size
    end
    return ok, err
end

function buffer:flush()
    if not self.buffer then return end
    if #self.buffer == 0 then return end
    if self.mode == "r" then
        -- Flushing read makes like no fucking sense
        return
    end

    -- ASSUMES WRITES ARE ATOMIC
    -- FAT16 GO KYS
    local ok, err = self.stream.write(self.stream.resource, self.buffer)
    if ok then
        self.buffer = ""
    end
    return ok, err
end

-- Not super well optimized but who cares
---@param chunk string
function buffer:putchunk(chunk)
    if not self.buffer then return end -- no buffer means eof
    if self.mode == "r" then
        self.buffer = ""
        return self.stream.write(self.stream.resource, chunk)
    end
    if self.buffering == "no" then
        return self.stream.write(self.stream.resource, chunk)
    end
    self.buffer = self.buffer .. chunk
    if self.buffering == "line" then
        if self.buffer:find("\n") then
            return self:flush()
        end
    elseif #self.buffer >= self.buflen then
        return self:flush()
    end
    return true, ""
end

function buffer:eof()
    return self.buffer == nil
end

local eot = string.char(4)

---@return string?
function buffer:getchunk()
    if not self.buffer then return end
    if self.closed then return end
    if self.mode == "r" then
        -- read from buffer
        if self.buffer == "" then
            self.buffer = self.stream.read(self.stream.resource, self.buflen)
            if not self.buffer then return end
        end
        local chunk = self.buffer
        if not chunk then return chunk end
        self.buffer = ""
        local eotLoc = chunk:find(eot)
        if self.text and eotLoc then
            chunk = chunk:sub(1, eotLoc-1)
            self.buffer = nil -- pretend file is closed
            self.closed = true
            return -- return EoF.
        end
        return chunk
    end

    self:flush()
    return (self.stream.read(self.stream.resource, 1))
end

---@param chunk string
function buffer:savechunk(chunk)
    if self.mode ~= "r" then return end
    self.buffer = (self.buffer or "") .. chunk
end

function buffer:remainingBufferSpace()
    local remaining = self.buflen - #self.buffer
    if remaining == math.huge then return #self.buffer end
    return remaining
end

---@param r number|"a"|"*a"|"l"|"*l"|"L"|"*L"|"n"|"*n"
function buffer:readSingle(r)
    if type(r) == "number" then
        r = math.floor(r)
        local data = ""
        while true do
            local c = self:getchunk()
            if not c then break end
            data = data .. c
            if #data == r then break end
            coroutine.yield()
        end
        self:savechunk(data:sub(r+1))
        return data:sub(1, r)
    end
    if r:sub(1,1) == "*" then r = r:sub(2) end
    r = r:sub(1, 1)
    if r == "a" then
        local data = ""
        while true do
            local c = self:getchunk()
            if not c then break end
            data = data .. c
            coroutine.yield()
        end
        if #data == 0 then return end
        return data
    end
    if r:lower() == "l" then
        local data = ""
        while true do
            local c = self:getchunk()
            if not c then return end
            data = data .. c
            -- we check chunk cuz its faster
            if c:find("\n") then break end
            coroutine.yield()
        end
        local eol = data:find("\n")
        if not eol then return end -- no newline, no lines
        if r == "L" then
            self:savechunk(data:sub(eol+1))
            return data:sub(1, eol)
        end
        self:savechunk(data:sub(eol+1))
        return data:sub(1, eol-1)
    end
end

function buffer:read(...)
    -- This might be the worst Lua code ever written
    local t = {...}
    local c = #t
    for i=1,c do
        t[i] = self:readSingle(t[i])
    end
    return table.unpack(t, 1, c)
end

function buffer:lines(...)
    local t = {...}
    if #t == 0 then t[1] = "l" end
    return function()
        return self:read(table.unpack(t))
    end
end

function buffer:write(...)
    local t = {...}
    for i=1,#t do
        t[i] = tostring(t[i])
    end
    local s = table.concat(t)
    while #s > 0 do
        local chunkSize = self:remainingBufferSpace()
        local chunk = s:sub(1, chunkSize)
        s = s:sub(chunkSize+1)
        local ok, err = self:putchunk(chunk)
        if not ok then return ok, err end
        -- no yield, just don't write 4 TB at once
    end
    return true, ""
end

---@param whence? seekwhence
---@param off? integer
function buffer:seek(whence, off)
    whence = whence or "cur"
    off = off or 0
    self:flush()
    self.buffer = ""
    return self.stream.seek(self.stream.resource, whence, off)
end

function buffer:close()
    self:flush()
    self.buffer = nil
    self.closed = true
    return self.stream.close(self.stream.resource)
end

function buffer:ioctl(action, ...)
    return self.stream.ioctl(self.stream.resource, action, ...)
end

return buffer
