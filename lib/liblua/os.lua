---@diagnostic disable: duplicate-set-field
local io = require("io")
local sys = require("syscalls")
local process = require("process")

function os.getenv(env)
    return (sys.getenv(env))
end

function os.getenvs()
    return (sys.getenvs())
end

function os.setenv(name, val)
    return sys.setenv(name, val)
end

function os.remove(filename)
    return sys.remove(filename)
end

function os.exit(code)
    sys.exit(code or 0)
end

os.touch = io.touch
os.exists = io.exists

function os.tmpname()
    local t = math.floor(os.time())
    while true do
        local p = "/tmp/lua_tmpf_" .. t
        if not os.exists(p) then return p end
        t = t + 1
    end
end

---@return string?
function os.getShell()
    local path = os.getenv("SHELL") or "/bin/sh"
    if not os.exists(path) then return end
    return path
end

---@param command string
---@param files? {[integer]: buffer}
function os.spawnCmd(command, files)
    local shPath = os.getShell()
    if shPath then
        -- Run actual shell
        return process.exec(shPath, "-c", command)
    end
    -- Emulated shell.
    -- Worst shell parser there is btw
    local args = string.split(command, " ")
    local cmd = table.remove(args, 1)
    cmd = io.searchpath(cmd)
    if not cmd then
        return nil, "missing command"
    end
    return process.spawn(cmd, {
        args = args,
        files = files,
    })
end

---@param command string
function os.execute(command)
    local p = assert(os.spawnCmd(command))
    p:wait()
    ---@type integer
    local e = p:status()
    p:forceKill()
    return e == 0, "exit", e
end

return os
