-- Only defines globals lol
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

function print(...)
    io.write(table.concat({...}, "\t"), "\n")
end

---@diagnostic disable-next-line: lowercase-global
function printf(fmt, ...)
    print(string.format(fmt, ...))
end
