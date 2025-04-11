---@diagnostic disable: inject-field
local sys = _G

function sys.open(path, mode)
    local err, fd = syscall("open", path, mode)
    return fd, err
end

function sys.close(fd)
    local err = syscall("close", fd)
    return err == nil, err
end

function sys.write(fd, data)
    local err = syscall("write", fd, data)
    return err == nil, err
end

function sys.read(fd, len)
    local err, data = syscall("read", fd, len)
    return data, err
end

function sys.seek(fd, whence, off)
    local err, pos = syscall("seek", fd, whence, off)
    return pos, err
end
