---@class libkvm
---@field vm integer
local kvm = {}
kvm.__index = kvm
kvm.version = "libkvm v0.-1.1"
local sys = require("syscalls")
local terminal = require("terminal")

function kvm.open(name)
    local fd, err = sys.kvmopen(name)
    if not fd then return nil, err end
    return setmetatable({
        vm = fd,
    }, kvm)
end

---@param action string
---@return ..any
function kvm:ioctl(action, ...)
    return sys.ioctl(self.vm, action, ...)
end

---@return boolean, any
function kvm:resume()
---@diagnostic disable-next-line: return-type-mismatch
    return self:ioctl("resume")
end

---@return _G
function kvm:namespace()
    return assert(self:ioctl("env"))
end

---@return "running"|"halted"|"restart"
function kvm:mode()
    return assert(self:ioctl("mode"))
end

---@param err? string
function kvm:traceback(err)
    return assert(self:ioctl("traceback", err))
end

---@vararg string
function kvm:listen(...)
    assert(self:ioctl("listen", ...))
end

---@vararg string
function kvm:forget(...)
    assert(self:ioctl("forget", ...))
end

---@param component KOCOS.VComponent
---@return string
function kvm:add(component)
    return assert(self:ioctl("add", component))
end

---@param slot? integer
---@return string
function kvm:addVGPU(slot)
    return assert(self:ioctl("addVGPU", slot))
end

---@param code string
---@param data string
---@param label? string
---@return string
function kvm:addBIOS(code, data, label)
    return assert(self:ioctl("addBIOS", code, data, label))
end

---@param component string
function kvm:remove(component)
    assert(self:ioctl("remove", component))
end

---@param component? string
---@return string
function kvm:tmp(component)
    return assert(self:ioctl("tmp", component))
end

---@return string
function kvm:address()
    return assert(self:ioctl("address"))
end

---@param address string
---@return string
function kvm:pass(address)
    for addr in component.list() do
        if addr:sub(1, #address) == address then
            address = addr
            break
        end
    end
    return assert(self:ioctl("pass", address))
end

---@class libkvm.kocosConfig
---@field files? {[integer]: integer}
---@field subenv? {[string]: string}
---@field componentFetch? fun(type?: string, exact?: boolean): {[string]: string}
---@field validatePassthrough? fun(address: string): boolean, string?
---@field validateMount? fun(path: string): boolean, string?

-- Adds a KOCOS virtual component
-- The KOCOS virtual component supports querying host information
-- And reading and writing from actual stdout/stdin of the host.
-- It is often used for TTY sharing between the host and virtual machine.
-- It is supported by the KOCOS kernel and most operating systems which use it.
---@param config? libkvm.kocosConfig
---@return string
function kvm:addKocos(config)
    config = config or {}
    local files = config.files or {[0]=0, [1]=1, [2]=2}
    local subenv = config.subenv
    local validatePassthrough = config.validatePassthrough or function() return false, "permission denied" end
    local validateMount = config.validateMount or function() return false, "permission denied" end
    return self:add {
        type = "kocos",
        slot = -1,
        close = function() end,
        internal = {},
        docs = {},
        methods = {
            getHost = function()
                return _OSVERSION
            end,
            getHypervisor = function()
                return kvm.version
            end,
            getKernel = function()
                return _KVERSION
            end,
            getHostEnv = function(env)
                if subenv then return subenv[env] end
                return os.getenv(env)
            end,
            getName = function()
                return self:ioctl("name")
            end,
            getHostComponents = config.componentFetch or function()
                return setmetatable({}, {__call = function() end})
            end,
            requestPassthrough = function(address)
                local ok, reason = validatePassthrough(address)
                if not ok then return nil, reason end
                return self:pass(address)
            end,
            requestMount = function(path)
                local ok, reason = validateMount(path)
                if not ok then return nil, reason end
                if io.ftype(path) == "directory" then
                    return self:addFilesystem(path, path)
                elseif io.ftype(path) == "file" then
                    local fd = assert(sys.open(io.resolved(path), "w"))
                    return self:addDrive(fd, path, nil, true)
                else
                    error("missing")
                end
            end,
            hasStdio = function()
                -- stdout, stdin and stderr
                return files[0] ~= nil and files[1] ~= nil and files[2] ~= nil
            end,
            remove = function(address)
                checkArg(1, address, "string")
                self:remove(address)
                return true
            end,
            write = function(fd, data)
                if not files[fd] then error("bad file descriptor") end
                assert(sys.write(files[fd], data))
                return true
            end,
            read = function(fd, len)
                if not files[fd] then error("bad file descriptor") end
                local data, err = sys.read(files[fd], len)
                if err then error(err) end
                return data
            end,
        },
    }
end

---@param directory string
---@param label? string
---@param slot? integer
---@param readOnly? boolean
function kvm:addFilesystem(directory, label, slot, readOnly)
    directory = io.resolved(directory)
    -- Nil on escapes
    -- No sandbox escapes for you
    local function getPath(path)
        local p = io.join(directory, path)
        if (p ~= directory) and (not string.startswith(p, directory .. "/")) then return end
        return p
    end

    local fdMap = {}

    return self:add {
        type = "filesystem",
        slot = slot or -1,
        close = function()
            for _, fd in pairs(fdMap) do
                sys.close(fd)
            end
        end,
        internal = {},
        docs = {},
        methods = {
            open = function(path, mode)
                mode = mode or "r"
                mode = mode:sub(1, 1) -- fuck you opencomputers
                if (mode == "w" or mode == "a") and readOnly then
                    error("unable to open in write mode")
                end
                path = assert(getPath(path), "invalid path")
                if mode ~= "r" then
                    if sys.ftype(path) == "missing" then
                        local ok, err = sys.touch(path, 2^16-1)
                        if err then _K.log("Error: %s", err) end
                        assert(ok, err)
                    end
                end
                local f, err = sys.open(path, mode)
                if err then _K.log("Error: %s", err) end
                assert(f, err)
                -- TODO: handle OOM case
                fdMap[f] = f
                return f
            end,
            close = function(fd)
                fd = assert(fdMap[fd], "bad file descriptor")
                assert(sys.close(fd))
                return true
            end,
            write = function(fd, data)
                fd = assert(fdMap[fd], "bad file descriptor")
                assert(sys.write(fd, data))
                return true
            end,
            read = function(fd, len)
                fd = assert(fdMap[fd], "bad file descriptor")
                return sys.read(fd, len)
            end,
            seek = function(fd, whence, off)
                fd = assert(fdMap[fd], "bad file descriptor")
                return assert(sys.seek(fd, whence, off))
            end,
            spaceUsed = function()
                local info = assert(sys.stat(directory))
                return info.used
            end,
            spaceTotal = function()
                local info = assert(sys.stat(directory))
                return info.total
            end,
            isReadOnly = function()
                return not not readOnly
            end,
            makeDirectory = function(path)
                -- TODO: create parent as well
                path = assert(getPath(path), "bad path")
                assert(sys.mkdir(path, 2^16-1))
                return true
            end,
            remove = function(path)
                path = assert(getPath(path), "bad path")
                assert(sys.remove(path))
                return true
            end,
            size = function(path)
                path = assert(getPath(path), "bad path")
                return sys.stat(path).size
            end,
            exists = function(path)
                path = assert(getPath(path), "bad path")
                return sys.ftype(path) ~= "missing"
            end,
            isDirectory = function(path)
                path = assert(getPath(path), "bad path")
                return sys.ftype(path) == "directory"
            end,
            rename = function()
                -- TODO: figure out how to implement this
                error("unimplemented")
            end,
            list = function(path)
                path = assert(getPath(path), "bad path")
                return io.list(path)
            end,
            lastModified = function(path)
                path = assert(getPath(path), "bad path")
                local info = assert(sys.stat(path))
                return info.mtime * 1000
            end,
            getLabel = function()
                return label
            end,
            setLabel = function(newLabel)
                label = newLabel
                return label
            end,
        },
    }
end

-- Adds a VGPU-compatible screen using the terminal library as a backend
-- Returns screen, keyboard
function kvm:addTUI()
    local keyboard = self:add {
        type = "keyboard",
        slot = -1,
        close = function() end,
        methods = {},
        docs = {},
        internal = {},
    }
    local isOn = true

    local maxWidth, maxHeight = terminal.maxResolution()
    terminal.setResolution(maxWidth, maxHeight)
    terminal.setForeground(0xFFFFFF)
    terminal.setBackground(0x000000)
    ---@type {[integer]: {w: integer, h: integer, fg: integer, bg: integer}}
    local buffers = {
        [0] = {
            w = maxWidth,
            h = maxHeight,
            fg = 0xFFFFFF,
            bg = 0,
        },
    }
    ---@type integer
    local activeBuffer = 0

    return self:add {
        type = "screen",
        slot = -1,
        close = function()
            terminal.reset()
            terminal.clear()
        end,
        methods = {
            isOn = function()
                return isOn
            end,
            turnOn = function()
                local wasOn = isOn
                isOn = true
                return wasOn, isOn
            end,
            turnOff = function()
                local wasOn = isOn
                isOn = false
                return wasOn, isOn
            end,
            getAspectRatio = function()
                return 1, 1
            end,
            getKeyboards = function()
                return {keyboard}
            end,
            setPrecise = function()
                return false
            end,
            isPrecise = function()
                return false
            end,
            setTouchModeInverted = function()
                return false
            end,
            isTouchModeInverted = function()
                return false
            end,
        },
        docs = {},
        internal = {
            vgpu = {
                reset = function()
                    terminal.clear()
                    terminal.reset()
                end,
                getForeground = function()
                    return buffers[activeBuffer].fg
                end,
                setForeground = function(color)
                    buffers[activeBuffer].fg = color
                    terminal.setForeground(color)
                end,
                getBackground = function()
                    return buffers[activeBuffer].bg
                end,
                setBackground = function(color)
                    buffers[activeBuffer].bg = color
                    terminal.setBackground(color)
                end,
                maxDepth = function()
                    return 8
                end,
                getDepth = function()
                    return 8
                end,
                setDepth = function()
                    -- can't change color depth
                end,
                maxResolution = function()
                    return maxWidth, maxHeight
                end,
                getResolution = function()
                    return buffers[activeBuffer].w, buffers[activeBuffer].h
                end,
                setResolution = function(w, h)
                    if activeBuffer ~= 0 then return end
                    local oldW, oldH = buffers[0].w, buffers[0].h
                    buffers[0].w = w
                    buffers[0].h = h
                    return oldW ~= w or oldH ~= h
                end,
                get = function(x, y)
                    return terminal.get(x, y, activeBuffer)
                end,
                set = function(x, y, v, vertical)
                    if vertical then error("unsupported") end -- todo: emulate
                    terminal.set(x, y, v, activeBuffer)
                    return true
                end,
                copy = function(x, y, w, h, tx, ty)
                    terminal.copy(x, y, w, h, tx ,ty, activeBuffer)
                    return true
                end,
                fill = function(x, y, w, h, c)
                    terminal.fill(x, y, w, h, c, activeBuffer)
                    return true
                end,
                getActiveBuffer = function()
                    return activeBuffer
                end,
                setActiveBuffer = function(buffer)
                    if not buffers[activeBuffer] then return false end
                    activeBuffer = buffer
                    terminal.setForeground(buffers[activeBuffer].fg)
                    terminal.setBackground(buffers[activeBuffer].bg)
                    return true
                end,
                buffers = function()
                    local buf = {}
                    for id in pairs(buffers) do
                        table.insert(buf, id)
                    end
                    table.sort(buf) -- consistency
                    return buf
                end,
                allocateBuffer = function(w, h)
                    w = w or maxWidth
                    h = h or maxHeight
                    local buf = assert(terminal.allocateBuffer(w, h))
                    buffers[buf] = {
                        w = w,
                        h = h,
                        fg = 0xFFFFFF,
                        bg = 0xFFFFFF,
                    }
                    return buf
                end,
                freeBuffer = function(b)
                    b = b or activeBuffer
                    if b == 0 then return true end
                    if not buffers[b] then return false end
                    terminal.freeBuffer(b)
                    buffers[b] = nil
                    return true
                end,
                freeAllBuffers = function()
                    buffers = {
                        [0] = buffers[0], -- worst code ever written
                    }
                    terminal.freeAllBuffers()
                    return true
                end,
                totalMemory = function()
                    return terminal.totalMemory()
                end,
                freeMemory = function()
                    return terminal.freeMemory()
                end,
                getBufferSize = function(b)
                    if not buffers[b] then return nil, nil end
                    return buffers[b].w, buffers[b].h
                end,
                bitblt = function(dst, x, y, w, h, src, fx, fy)
                    dst = dst or 0
                    x = x or 1
                    y = y or 1
                    if not buffers[dst] then return false end
                    w = w or buffers[dst].w
                    h = h or buffers[dst].h
                    src = src or activeBuffer
                    fx = fx or 1
                    fy = fy or 1
                    if not buffers[src] then return false end
                    terminal.memcpy(src, fx, fy, w, h, dst, x, y)
                    return true
                end,
            },
        },
    }, keyboard
end

-- TODO: drive methods

---@param fd integer
---@param label? string
---@param slot? integer
---@param closeOnExit? boolean
function kvm:addDrive(fd, label, slot, closeOnExit)
    return self:add {
        type = "drive",
        slot = slot or -1,
        close = function()
            if closeOnExit then
                assert(sys.close(fd))
            end
        end,
        docs = {},
        internal = {},
        methods = {
            -- TODO: drive methods
        },
    }
end

return kvm
