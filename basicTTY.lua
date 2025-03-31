local KOCOS = _K

-- Syscall definitions (no liblua :sad:)

local pnext, pinfo, open, mopen, close, write, read, queued, clear, pop, ftype, list

function pnext(pid)
    local err, npid = syscall("pnext", pid)
    return npid, err
end

function pinfo(pid)
    local err, info = syscall("pinfo", pid)
    return info, err
end

function open(path, mode)
    local err, fd = syscall("open", path, mode)
    return fd, err
end

function mopen(mode, contents, limit)
    local err, fd = syscall("mopen", mode, contents, limit)
    return fd, err
end

function close(fd)
    local err = syscall("close", fd)
    return err ~= nil, err
end

function write(fd, data)
    local err = syscall("write", fd, data)
    return err ~= nil, err
end

function read(fd, len)
    local err, data = syscall("read", fd, len)
    return data, err
end

function queued(fd, ...)
    local err, isQueued = syscall("queued", fd, ...)
    return isQueued, err
end

function clear(fd)
    local err = syscall("clear", fd)
    return err ~= nil, err
end

function pop(fd, ...)
    return syscall("pop", fd, ...)
end

function ftype(path)
    local err, x = syscall("ftype", path)
    return x, err
end

function list(path)
    local err, x = syscall("list", path)
    return x, err
end

local logPid

do
    local attempt = assert(pnext())
    while true do
        local info = assert(pinfo(attempt))
        if info.cmdline == "OS:logproc" then
            logPid = attempt
            break
        end
        attempt = pnext(attempt)
        if not attempt then break end
    end
end

assert(logPid, "log pid failed")

syscall("pwait", logPid)

local tty = _K.tty.create(_OS.component.gpu, _OS.component.screen)

tty:clear()

local stdout = assert(mopen("w", "", math.huge))
local stdin = assert(mopen("w", "", math.huge))

_K.process.spawn("/internetTest.lua", {})

local commandStdinBuffer = ""
local function readLine()
    while true do
        commandStdinBuffer = commandStdinBuffer .. assert(read(stdin, math.huge))
        local lineEnd = commandStdinBuffer:find('%\n')
        if lineEnd then
            local line = commandStdinBuffer:sub(1, lineEnd-1)
            commandStdinBuffer = commandStdinBuffer:sub(lineEnd+1)
            return line
        else
            coroutine.yield()
        end
    end
end

local function myBeloved()
    while true do
        write(stdout, "> ")
        local line = readLine()

        -- Basic program that traverses filesystem

        local t = ftype(line)

        if t == "file" then
            -- cat
            local f = assert(open(line, "r"))
            local total = 0
            local maximum = 65536
            while true do
                local chunk, err = read(f, 1024)
                if err then error(err) end
                if not chunk then break end
                total = total + #chunk
                if total >= maximum then
                    write(stdout, "...")
                    break
                end
                write(stdout, chunk)
                coroutine.yield()
            end
            close(f)
            write(stdout, "\n")
        elseif t == "directory" then
            -- ls
            local files = assert(list(line))
            for i=1,#files do
                local file = files[i]
                write(stdout, file .. "\n")
            end
        else
            write(stdout, "Error: Not a file\n")
        end

        coroutine.yield()
    end
end

syscall("attach", myBeloved, "command")

local function isEscape(char)
    return char < 0x20 or (char >= 0x7F and char <= 0x9F)
end

local inputBuffer
while true do
    if queued(stdout, "write") then
        local data, err = read(stdout, math.huge)
        if err then tty:write(err) end
        clear(stdout)
        assert(data, "no data")
        tty:write(data)
        coroutine.yield()
    end

    if queued(stdin, "read") and not inputBuffer then
        clear(stdin)
        inputBuffer = ""
    end

    if inputBuffer then
        local ok, _, char, code = _K.event.pop("key_down")
        if ok then
            local lib = unicode or string
            local backspace = 0x0E
            local enter = 0x1C
            if code == enter then
                clear(stdin)
                write(stdin, inputBuffer .. "\n")
                tty:write('\n')
                inputBuffer = nil
            elseif code == backspace then
                local t = lib.sub(inputBuffer, -1)
                tty:unwrite(t)
                inputBuffer = lib.sub(inputBuffer, 1, -2)
            elseif not isEscape(char) then
                tty:write(lib.char(char))
                inputBuffer = inputBuffer .. lib.char(char)
            end
        end
    end

    coroutine.yield()
end
