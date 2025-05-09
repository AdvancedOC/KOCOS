-- Only defines globals lol
---@diagnostic disable: lowercase-global
local sys = require("syscalls")
local io = require("io")

---@param filename string
---@param mode? "b"|"t"|"bt"
---@param env? _G
function loadfile(filename, mode, env)
    local f, err = sys.open(filename, "r")
    if not f then return nil, err end
    local data = ""
    while true do
        local chunk, err = sys.read(f, math.huge)
        if err then sys.close(f) return nil, err end
        if not chunk then break end
        data = data .. chunk
    end
    return load(data, "=" .. filename, mode, env)
end

---@param filename string
function dofile(filename)
    return assert(loadfile(filename))()
end

local function makeConcatable(...)
    local t = {...}
    for i=1,#t do
        t[i] = tostring(t[i])
    end
    return t
end

function print(...)
    io.write(table.concat(makeConcatable(...), "\t"), "\n")
end

function eprint(...)
    io.stderr:write(table.concat(makeConcatable(...), "\t"), "\n")
end

function printf(fmt, ...)
    print(string.format(fmt, ...))
end

function eprintf(fmt, ...)
    eprint(string.format(fmt, ...))
end
