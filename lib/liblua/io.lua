---@diagnostic disable: duplicate-set-field, redundant-parameter
io = {}

---@alias iomode "w"|"r"|"a"|"wb"|"rb"|"ab"

local sys = require("syscalls")
local buffer = require("buffer")

local file = {}
file.__index = file

file.write = sys.write
file.read = sys.read
file.seek = sys.seek
file.close = sys.close
file.ioctl = sys.ioctl

---@param path string
---@return string
function io.canonical(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")
    local stack = {}

    for _, part in ipairs(parts) do
        if #part > 0 then
            table.insert(stack, part)
            if part == string.rep(".", #part) then
                for _=1,#part do
                    stack[#stack] = nil
                end
            end
        end
    end

    return "/" .. table.concat(stack, "/")
end

function io.join(...)
    return io.resolved(table.concat({...}, "/"))
end

---@param path string
function io.mkrelative(path)
    local cwd = io.cwd()
    if string.startswith(path, cwd .. "/") then
        return path:sub(#cwd + 2)
    end
    return path
end

---@return string
function io.cwd()
    return sys.getenv("CWD") or "/"
end

---@return string
function io.cd(cwd)
    cwd = io.resolved(cwd)
    assert(io.ftype(cwd) == "directory", "not a directory")
    assert(sys.setenv("CWD", cwd))
end

---@param path string
---@return string
function io.resolved(path)
    if path:sub(1, 1) ~= "/" then
        path = io.cwd() .. "/" .. path
    end
    return io.canonical(path)
end

---@param fd integer
---@param mode iomode
---@return buffer
function io.from(fd, mode)
    local stream = setmetatable({resource = fd}, file)
    return buffer.wrap(stream, mode)
end

---@param mode? iomode
---@param contents? string
---@param limit? integer
function io.tmpfile(mode, contents, limit)
    mode = mode or "w"
    contents = contents or ""
    limit = limit or math.huge
    local fd, err = sys.mopen(mode:sub(1, 1), contents, limit)
    if err then return nil, err end
    return io.from(fd, mode)
end

---@param filename string
---@param mode? iomode
---@return buffer?, string?
function io.open(filename, mode)
    filename = io.resolved(filename)
    mode = mode or "r"
    local fd, err = sys.open(filename, mode:sub(1, 1))
    if err then return nil, err end
    return io.from(fd, mode), nil
end

---@param inFile? buffer
---@param outFile? buffer
function io.mkpipe(inFile, outFile)
    ---@diagnostic disable-next-line: cast-local-type
    inFile = inFile or assert(io.tmpfile())

    ---@diagnostic disable-next-line: cast-local-type
    outFile = outFile or assert(io.tmpfile())

    local fd, err = sys.mkpipe(inFile:unwrap(), outFile:unwrap())
    if err then return nil, err end
    return io.from(fd, "w")
end

function io.ftype(path)
    path = io.resolved(path)
    return sys.ftype(path)
end

function io.exists(path)
    return io.ftype(path) ~= "missing"
end

function io.mkdir(path, permissions)
    path = io.resolved(path)
    -- TODO: make permissions default to process perms
    return sys.mkdir(path, permissions)
end

function io.touch(path, permissions)
    path = io.resolved(path)
    -- TODO: make permissions default to process perms
    return sys.touch(path, permissions)
end

function io.list(path)
    path = io.resolved(path)
    -- TODO: make permissions default to process perms
    return sys.list(path)
end

local stdout, stdin = io.from(0, "w"), io.from(1, "r")

io.stdout = stdout
io.stdin = stdin
io.stderr = io.from(2, "w")

function io.write(...)
    return stdout:write(...)
end

function io.read(...)
    io.flush()
    return stdin:read(...)
end

---@param f? string|buffer
---@return buffer
function io.input(f)
    if not f then return stdin end
    if type(f) == "string" then
        f = assert(io.open(f, "r"))
    end
    stdin = f
    return stdin
end

---@param f? string|buffer
---@return buffer
function io.output(f)
    if not f then return stdout end
    if type(f) == "string" then
        f = assert(io.open(f, "r"))
    end
    stdout = f
    return stdout
end

function io.flush()
    return stdout:flush()
end

---@param f? buffer
function io.close(f)
    f = f or stdout
    f:close()
end

return io
