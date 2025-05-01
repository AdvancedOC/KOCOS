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
---@param bufmode? iomode
function io.tmpfile(mode, contents, limit, bufmode)
    mode = mode or "r"
    contents = contents or ""
    limit = limit or math.huge
    bufmode = bufmode or "w"
    local fd, err = sys.mopen(mode:sub(1, 1), contents, limit)
    if err then return nil, err end
    return io.from(fd, bufmode)
end

---@param filename string
---@param mode? iomode
---@return buffer?, string?
function io.open(filename, mode)
    filename = io.resolved(filename)
    mode = mode or "r"
    if mode:sub(1, 1) ~= "r" and not io.exists(filename) then
        local ok, err = io.touch(filename, 2^16-1)
        if not ok then return nil, err end
    end
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

function io.chown(path, permissions)
    path = io.resolved(path)
    -- TODO: make permissions default to process perms
    return sys.chown(path, permissions)
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

-- Checks for files line the shell would
---@param name string
---@param path? string
---@param extensions? string
---@param sep? string
---@return string?
function io.searchpath(name, path, extensions, sep, allowCWD)
    path = path or sys.getenv("PATH") or "/:/sbin:/bin:/usr/bin:/usr/local/bin:/mnt/bin:/mnt/local/bin"
    extensions = extensions or ".lua:.kelp:.o"
    sep = sep or ':'
    if allowCWD == nil then allowCWD = true end
    if allowCWD then path = path .. sep .. io.cwd() end

    local fextensions = string.split(extensions, sep)
    table.insert(fextensions, 1, "")
    local parts = string.split(path, sep)
    for _, ext in ipairs(fextensions) do
        for _, dir in ipairs(parts) do
            local p = io.join(dir, name .. ext)
            if io.exists(p) then
                return p
            end
        end
    end
end

---@param path string
function io.stat(path)
    return sys.stat(io.resolved(path))
end

---@param path string
function io.parentOf(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    path = path:reverse()
    local l = path:find("/", nil, true)
    if l then return path:sub(l+1):reverse() end
    return ""
end

---@param path string
function io.nameOf(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    path = path:reverse()
    local l = path:find("/", nil, true)
    if l then path = path:sub(1, l-1) end
    return path:reverse()
end

return io
