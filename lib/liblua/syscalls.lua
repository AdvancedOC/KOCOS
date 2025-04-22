---@diagnostic disable: inject-field
local sys = {}

function sys.open(path, mode)
    local err, fd = syscall("open", path, mode)
    return fd, err
end

function sys.touch(path, permissions)
    local err = syscall("touch", path, permissions)
    return err == nil, err
end

function sys.mkdir(path, permissions)
    local err = syscall("mkdir", path, permissions)
    return err == nil, err
end

function sys.remove(path)
    local err = syscall("remove", path)
    return err == nil, err
end

function sys.stat(path)
    local err, info = syscall("stat", path)
    return info, err
end

function sys.mopen(mode, contents, limit)
    local err, fd = syscall("mopen", mode, contents, limit)
    return fd, err
end

function sys.mkpipe(inFD, outFD)
    local err, fd = syscall("mkpipe", inFD, outFD)
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

function sys.ioctl(fd, action, ...)
    return syscall("ioctl", fd, action, ...)
end

function sys.ftype(path)
    local err, t = syscall("ftype", path)
    return t, err
end

function sys.list(path)
    local err, l = syscall("list", path)
    return l, err
end

function sys.exit(status)
    local err = syscall("exit", status)
    return err == nil, err
end

function sys.getenv(env)
    local err, val = syscall("getenv", env)
    return val, err
end

function sys.getenvs()
    local err, vals = syscall("getenvs")
    return vals, err
end

function sys.setenv(env, val)
    local err = syscall("setenv", env, val)
    return err == nil, err
end

function sys.pself()
    local err, pid = syscall("pself")
    return pid, err
end

function sys.pnext(pid)
    local err, npid = syscall("pnext", pid)
    return npid, err
end

function sys.pawait(pid)
    local err = syscall("pawait", pid)
    return err == nil, err
end

function sys.pwait(pid)
    local err = syscall("pwait", pid)
    return err == nil, err
end

function sys.pinfo(pid)
    local err, info = syscall("pinfo", pid)
    return info, err
end

function sys.pstatus(pid)
    local err, info = syscall("pstatus", pid)
    return info, err
end

function sys.pexit(pid)
    local err = syscall("pexit", pid)
    return err == nil, err
end

function sys.pspawn(init, conf)
    local err, pid = syscall("pspawn", init, conf)
    return pid, err
end

function sys.psignal(pid, event, ...)
    local err = syscall("psignal", pid, event, ...)
    return err == nil, err
end

return sys
