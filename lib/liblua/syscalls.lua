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

function sys.kvmopen(name)
    local err, fd = syscall("kvmopen", name)
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
    local t = {syscall("ioctl", fd, action, ...)}
    if t[1] then
        return nil, t[1]
    end
    return table.unpack(t, 2)
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

function sys.pstatus(pid, status)
    local err = syscall("pstatus", pid, status)
    return err == nil, err
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

function sys.cprimary(type)
    local err, p = syscall("cprimary", type)
    return p, err
end

function sys.cproxy(addr)
    local err, p = syscall("cproxy", addr)
    return p, err
end

function sys.ctype(addr)
    local err, t = syscall("ctype", addr)
    return t, err
end

function sys.clist(all)
    local err, l = syscall("clist", all)
    return l, err
end

function sys.cinvoke(addr, method, ...)
    return syscall("cinvoke", addr, method, ...)
end

-- If hostname is nil, it just returns
-- If hostname is not nil, it will set the name and return
-- the new name
function sys.hostname(hostname)
    local err, name = syscall("hostname", hostname)
    return name, err
end

return sys
