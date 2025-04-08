local KOCOS = _K

-- Syscall definitions (no liblua :sad:)

local pnext, pinfo, open, mopen, close, write, read, queued, clear, pop, ftype, list, stat, cstat, touch, mkdir, remove

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
    return err == nil, err
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
    return err == nil, err
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

function stat(path)
    local err, info = syscall("stat", path)
    return info, err
end

function cstat()
    local err, info = syscall("cstat")
    return info, err
end

function touch(path, perms)
    local err = syscall("touch", path, perms)
    return err == nil, err
end

function mkdir(path, perms)
    local err = syscall("mkdir", path, perms)
    return err == nil, err
end

function remove(path)
    local err = syscall("remove", path)
    return err == nil, err
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

---@param rawArgs string[]
---@return string[], {[string]: string}
local function parse(rawArgs)
    local args, opt = {}, {}

    for i=1,#rawArgs do
        local a = rawArgs[i]

        if a:sub(1, 2) == "--" then
            local assign = a:find("=", nil, true)
            if assign then
                local key = a:sub(3, assign-1)
                local value = a:sub(assign+1)
                opt[key] = value
            else
                opt[a:sub(3)] = ""
            end
        elseif a:sub(1, 1) == "-" then
            local f = a:sub(2)
            for j=1,#f do
                opt[f:sub(j, j)] = ""
            end
        else
            table.insert(args, a)
        end
    end

    return args, opt
end

local cmds = {}

local function print(...)
    local n = select("#", ...)
    for i=1,n do
        local s = select(i, ...)
        assert(write(stdout, tostring(s)))
        if i == n then
            assert(write(stdout, "\n"))
        else
            assert(write(stdout, "\t"))
        end
    end
end

local function printf(f, ...)
    local s = string.format(f, ...)
    assert(write(stdout, s))
    assert(write(stdout, "\n"))
end

function cmds.echo(...)
    local args, opts = parse(...)

    if opts.help or opts.h then
        print([[
echo - Print arguments

--help or -h - Prints this help page
--no-newline or -n - Does not print the last newline
--tab or -t - Use tabs as separator
]])
        return
    end

    local s = (opts.tab or opts.t) and "\t" or " "
    s = table.concat(args, s)
    assert(write(stdout, s))
    if not opts["no-newline"] and not opts.n then
        assert(write(stdout, "\n"))
    end
end

function cmds.ls(...)
    local args, opts = parse(...)

    if #args == 0 then table.insert(args, "/") end
    for i=1,#args do
        local p = args[i]
        assert(ftype(p) == "directory", p .. " is not a directory")

        print(p)
        ---@type string[]
        local l = assert(list(p))

        for j=1,#l do
            local f = l[j]
            local fp = (p .. "/" .. f):gsub("%/%/", "/")
            local data = f
            local info = assert(stat(fp))
            if opts.s or opts.h or opts.l then
                local size = info.size
                if opts.h then
                    data = string.memformat(size) .. " " .. data
                end
            end
            print("\t" .. data)
        end
    end
end

function cmds.cp(...)
    local args, opts = parse(...)

    local input = assert(args[1], "no input file")
    local output = assert(args[2], "no output file")

    local inFile, outFile, err, chunk, _

    inFile, err = open(input, "r")
    if err then error(err) end
    if ftype(output) == "missing" then
        _, err = touch(output, 2^16-1)
        if err then
            error(err)
        end
    end
    outFile, err = open(output, "w")
    if err then error(err) end

    while true do
        chunk, err = read(inFile, math.huge)
        if err then
            close(inFile)
            close(outFile)
            error(err)
        end
        if not chunk then break end

        _, err = write(outFile, chunk)
        if err then
            close(inFile)
            close(outFile)
            error(err)
        end
    end

    close(inFile)
    close(outFile)
end

function cmds.rm(...)
    local args, opts = parse(...)

    for i=1,#args do
        assert(remove(args[i]))
    end
end

function cmds.lsmnt(...)
    local data = {}

    for mount, part in _K.fs.mountedPartitions() do
        local drive = part.drive.address
        data[drive] = data[drive] or {}
        data[drive][part.uuid] = "/" .. mount
    end

    for drive, subdata in pairs(data) do
        print(drive)
        for part, mount in pairs(subdata) do
            local info = stat(mount)
            printf("\t%s %s %s %s", part, info.deviceName, mount, string.memformat(info.total))
        end
    end
end

function cmds.partcomp(...)
    local args, opts = parse(...)

    assert(args[1], "missing UUID")
    local part = _K.fs.partitionFromUuid(args[1], {
        allowFullDrivePartition = true,
        autocomplete = true,
    })
    if part then
        print(part.uuid)
    else
        print("missing")
    end
end

function cmds.lspart(...)
    local parts = _K.fs.findAllPartitions({allowFullDrivePartition = true, mountedOnly = false})
    for i=1,#parts do
        local part = parts[i]
        printf("%s %s %s (from %s)", part.uuid, part.name, string.memformat(part.byteSize), part.drive.address)
    end
end

function cmds.format(...)
    local args, opts = parse(...)
    local partUUID = assert(args[1], "missing partition")
    local fs = args[2] or "okffs"

    local part = assert(_K.fs.partitionFromUuid(partUUID), "partition not found")
    assert(_K.fs.format(part, fs))
end

function cmds.mount(...)
    local args, opts = parse(...)
    local partUUID = assert(args[1], "missing partition")
    local dir = args[2]
    local part = assert(_K.fs.partitionFromUuid(partUUID), "partition not found")
    assert(ftype(dir) == "directory", "mountpoint must be a directory")
    _K.fs.mount(dir, part)
end

function cmds.shutdown(...)
    _OS.computer.shutdown()
end

function cmds.reboot(...)
    _OS.computer.shutdown(true)
end

function cmds.stat(...)
    local args, opts = parse(...)

    for i=1,#args do
        local info = assert(stat(args[i]))

        print(args[i])
        print("\tType: " .. info.type)
        print("\tSize: " .. info.size)
        print("\tUsed: " .. info.used)
        print("\tTotal: " .. info.total)
        print("\tLast Modified: " .. os.date("%x %X", info.mtime))
        print("\tPartition: " .. info.partition)
        print("\tPartition Name: " .. info.deviceName)
        print("\tDrive Type: " .. info.driveType)
        print("\tDrive Name: " .. info.driveName)
    end
end

function cmds.touch(...)
    local args, opts = parse(...)

    for i=1,#args do
        -- 2^16-1 perms means everyone can do anything
        assert(touch(args[i], 2^16-1))
    end
end

function cmds.mkdir(...)
    local args, opts = parse(...)

    for i=1,#args do
        -- 2^16-1 perms means everyone can do anything
        assert(mkdir(args[i], 2^16-1))
    end
end

function cmds.cat(...)
    local args, opts = parse(...)

    if opts.help or opts.h or #args == 0 then
        print([[
cat - Concatenate files (stdin is forbidden currently)

--help or -h or no files - Prints this help page
--newline or -n - Print newline
--maximum=<maximum> - Set maximum amount of bytes
]])
    end

    local total = 0
    local maximum = tonumber(opts.maximum) or math.huge
    for i=1,#args do
        local path = args[i]
        local f, err = open(path, "r")
        if f then
            while true do
                local data, err = read(f, 16384)
                if err then close(f) error(err) end
                if not data then break end
                local allowed = maximum - total
                total = total + #data
                if allowed < #data then data = data:sub(1, allowed) end
                local _, err = write(stdout, data)
                if err then close(f) error(err) end
                if maximum ~= math.huge then
                    assert(write(stdout, "...\n"))
                end
                if total >= maximum then break end
                coroutine.yield()
            end
            close(f)
        else
            printf("cat: could not open %s: %s", path, err)
        end
    end

    if opts.newline or opts.n then
        assert(write(stdout, "\n"))
    end
end

function cmds.mem(...)
    local info = assert(cstat())
    local total = info.memTotal
    local used = total - info.memFree
    local usedf = string.memformat(used, " ")
    local totalf = string.memformat(total, " ")
    printf("%s / %s (%.2f%%)", usedf, totalf, used / total * 100)
end

function cmds.battery(...)
    local info = assert(cstat())
    printf("%d J / %d J (%.2f%%)", info.energy, info.maxEnergy, info.energy / info.maxEnergy * 100)
end

function cmds.uptime(...)
    local info = assert(cstat())
    local uptime = info.uptime
    local ms = tostring(math.floor((uptime * 1000) % 1000))
    local secs = tostring(math.floor(uptime) % 60)
    local mins = tostring(math.floor(uptime / 60) % 60)
    local hours = tostring(math.floor(uptime / 3600) % 60)

    while #ms < 3 do ms = "0" .. ms end
    while #secs < 2 do secs = "0" .. secs end
    while #mins < 2 do mins = "0" .. mins end
    while #hours < 2 do hours = "0" .. hours end

    printf("%s:%s:%s.%s", hours, mins, secs, ms)
end

function cmds.cstat(...)
    local info = assert(cstat())

    printf("Mem Free: %s / %s", string.memformat(info.memFree), string.memformat(info.memTotal))
    printf("Battery: %d J / %d J", info.energy, info.maxEnergy)
    printf("Thread Count: %d", info.threadCount)
    printf("Kernel: %s", info.kernel)
    printf("Uptime: %fs", info.uptime)
    printf("Boot: %s", info.boot)
    printf("TMP: %s", info.tmp)
    printf("Architecture: %s", info.arch)
    if info.isRobot then print("Robot") end
    if #info.users == 0 then table.insert(info.users, "none") end
    printf("Users: %s", table.concat(info.users))
end

---@param a string
---@param b string
---@return number
local function levenshtein(a, b)
    -- adapted from the haskell example in https://en.wikipedia.org/wiki/Levenshtein_distance#Computation
    if #a == 0 then return #b end
    if #b == 0 then return #a end

    local x = a:sub(1, 1)
    local s = a:sub(2)

    local y = b:sub(1, 1)
    local t = b:sub(2)

    if x == y then return levenshtein(s, t) end

    return 1 + math.min(
        levenshtein(a, t),
        levenshtein(s, b),
        levenshtein(s, t)
    )
end

local function myBeloved()
    while true do
        write(stdout, "> ")
        local line = readLine()

        -- Basic program that traverses filesystem
        local parts = string.split(line, " ")

        local cmd = parts[1]
        local args = {table.unpack(parts, 2)}
        if cmds[cmd] then
            local ok, err = xpcall(cmds[cmd], debug.traceback, args)
            if not ok then
                write(stdout, err)
                write(stdout, "\n")
            end
        else
            local bestMatch
            local bestDist = math.huge
            -- TODO: tweak it to be better
            local typoThreshold = 3
            for other in pairs(cmds) do
                local d = levenshtein(cmd, other)
                if d < bestDist and d < typoThreshold then
                    bestDist = d
                    bestMatch = other
                end
            end
            write(stdout, "Unknown command: " .. cmd .. "\n")
            if bestMatch then
                write(stdout, "Did you mean " .. bestMatch .. "?\n")
            end
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
