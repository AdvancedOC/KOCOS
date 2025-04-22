---@diagnostic disable: duplicate-set-field
local io = require("io")
local sys = require("syscalls")

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
