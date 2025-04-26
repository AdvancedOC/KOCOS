---@class libkvm
---@field vm integer
local kvm = {}
kvm.__index = kvm
kvm.version = "libkvm v0.-1.1"
local sys = require("syscalls")

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

    end
    return assert(self:ioctl("pass", address))
end

-- Adds a KOCOS virtual component
-- The KOCOS virtual component supports querying host information
-- And reading and writing from actual stdout/stdin of the host.
-- It is often used for TTY sharing between the host and virtual machine.
-- It is supported by the KOCOS kernel and most operating systems which use it.
---@param subenv? {[string]: string}
---@param files? {[integer]: integer}
---@return string
function kvm:addKocos(subenv, files)
    files = files or {[0]=0, [1]=1, [2]=2}
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
                return assert(os.getenv(env))
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
        close = function() end,
        internal = {},
        docs = {},
        methods = {
            open = function(path, mode)
                if mode == "w" and readOnly then
                    error("unable to open in write mode")
                end
                path = assert(getPath(path), "invalid path")
                local f = assert(sys.open(path, mode))
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
