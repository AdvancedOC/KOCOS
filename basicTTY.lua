local KOCOS = _K

-- Syscall definitions (no liblua :sad:)

local pnext, pinfo, open, mopen, close, write, read, queued, clear, pop, ftype, list, stat, cstat, touch, mkdir, remove, exit, listen, forget, mkpipe
local clist, cproxy, cinvoke, ctype, attach
local socket, serve, accept, connect

local function ttyopen(gpu, keyboard, config)
    local err, fd = syscall("ttyopen", gpu, keyboard, config)
    return fd, err
end

local function ioctl(fd, action, ...)
    local t = {syscall("ioctl", fd, action, ...)}
    if t[1] then
        return nil, t[1]
    end
    return table.unpack(t, 2)
end

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
    return err == nil, err
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

function exit(status)
    -- WILL NEVER RETURN IF IT WORKED
    local err = syscall("exit", status)
    return err == nil, err
end

function listen(f, id)
    local err, eid = syscall("listen", f, id)
    return eid, err
end

function forget(id)
    local err = syscall("forget", id)
    return err == nil, err
end

function mkpipe(input, output)
    local err, fd = syscall("mkpipe", input, output)
    return fd, err
end

function clist(all)
    local err, l = syscall("clist", all)
    return l, err
end

function cproxy(addr)
    local err, p = syscall("cproxy", addr)
    return p, err
end

function cinvoke(addr, ...)
    return syscall("cinvoke", addr, ...)
end

function ctype(addr)
    local err, t = syscall("ctype", addr)
    return t, err
end

function attach(func, name)
    local err, tid = syscall("attach", func, name)
    return tid, err
end

function socket(protocol, subdomain)
    local err, fd = syscall("socket", protocol, subdomain)
    return fd, err
end

function connect(fd, address, options)
    local err = syscall("connect", fd, address, options)
    return err == nil, err
end

function serve(fd, options)
    local err = syscall("serve", fd, options)
    return err == nil, err
end

function accept(fd)
    local err, clientfd = syscall("accept", fd)
    return clientfd, err
end

local graphics = nil
local keyboard = nil

if _OS.component.gpu then
    graphics = _OS.component.gpu
    local screen = _OS.component.screen
    graphics.bind(screen.address)
    keyboard = screen.getKeyboards()[1]
elseif _OS.component.kocos then
    graphics = _OS.component.kocos
    keyboard = "no keyboard"
end

assert(graphics, "unable to find rendering hardware")
assert(keyboard, "unable to find input hardware")

local tty = assert(ttyopen(graphics.address, keyboard))

local stdout = tty
local stdin = tty

local history = {}

local commandStdinBuffer = ""
local function readLine()
    local historyIndex = #history+1
    while true do
        local lineEnd = commandStdinBuffer:find('[%\n%\4]')
        if lineEnd then
            local line = commandStdinBuffer:sub(1, lineEnd-1)
            commandStdinBuffer = commandStdinBuffer:sub(lineEnd+1)
            table.insert(history, line)
            return line
        end
        -- TTY should never end
        local data = assert(read(stdin, -1))
        if string.find(data, "\t") then
            assert(write(stdin, "autocomplete unsupported\t"))
            data = ""
        elseif data == "\x11" then
            if #history > 0 then
                local l = history[historyIndex-1] or ""
                historyIndex = math.max(historyIndex - 1, 0)
                assert(write(stdin, l .. "\t"))
            else
                assert(write(stdin, "\t"))
            end
            data = ""
        elseif data == "\x12" then
            local l = history[historyIndex+1] or ""
            historyIndex = math.min(historyIndex + 1, #history+1)
            assert(write(stdin, l .. "\t"))
            data = ""
        end
        commandStdinBuffer = commandStdinBuffer .. data
        coroutine.yield()
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

function cmds.exit(...)
    exit(0)
end

function cmds.concealed(...)
    assert(write(stdout, "Super secret message:\x1b[8m"))
    local line = readLine()
    assert(write(stdout, "\x1b[0m\n" .. line .. "\n"))
end

local sysret = false
local sysignore = false

local function sysprint(name, sysfunc, a, r)
    if (name == "sysret") and (not sysret) then
        if sysignore then
            sysignore = false
            return
        end
        sysret = true
        a = table.copy(a)
        for i=1,#a do
            local ok, fmt = pcall(string.format, "%q", a[i])
            if ok then
                a[i] = fmt
            else
                a[i] = tostring(a[i])
            end
        end
        r = table.copy(r)
        local rlen = 1
        for i in pairs(r) do
            rlen = math.max(rlen, i)
            local ok, fmt = pcall(string.format, "%q", r[i])
            if ok then
                r[i] = type(fmt) == "string" and fmt or tostring(fmt)
            else
                r[i] = tostring(r[i])
            end
        end
        for i=1,rlen do
            if not r[i] then r[i] = "nil" end
        end
        local args = table.concat(a, ", ")
        local ret = table.concat(r, ", ")
        local s = string.format("%s(%s) = %s", sysfunc, args, ret)
        print(s)
        sysret = false
    end
end

listen(function(name, ...)
    if name == "event_err" then
        KOCOS.logAll(name, ...)
    end
end)

function cmds.strace(rawArgs)
    local c = cmds[rawArgs[1]]
    if not c then error("bad command") end
    sysignore = true
    local tracer = assert(listen(sysprint))
    c({table.unpack(rawArgs, 2)})
    assert(forget(tracer))
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

    local function color(x)
        if not (opts.c or opts.color) then return "" end
        return "\x1b[" .. tostring(x) .. "m"
    end

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
            local ft = assert(ftype(fp))
            local info = assert(stat(fp))
            local fc = 0
            if info.isMount then
                fc = 33
            elseif ft == "directory" then
                fc = 36
            elseif string.startswith(f, ".") then
                fc = 35
            elseif string.endswith(f, ".lua") then
                fc = 92
            end
            local data = color(fc) .. f .. color(0)
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

function cmds.unmount(...)
    local args, opts = parse(...)

    for i=1,#args do
        _K.fs.unmount(args[i])
    end
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
        print("\tIs Mount: " .. tostring(info.isMount))
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

-- Generated with https://patorjk.com/software/taag/#p=display&f=Big%20Money-ne&t=KOCOS
local kocosAsciiArt = [[
 /$$   /$$  /$$$$$$   /$$$$$$   /$$$$$$   /$$$$$$ 
| $$  /$$/ /$$__  $$ /$$__  $$ /$$__  $$ /$$__  $$
| $$ /$$/ | $$  \ $$| $$  \__/| $$  \ $$| $$  \__/
| $$$$$/  | $$  | $$| $$      | $$  | $$|  $$$$$$ 
| $$  $$  | $$  | $$| $$      | $$  | $$ \____  $$
| $$\  $$ | $$  | $$| $$    $$| $$  | $$ /$$  \ $$
| $$ \  $$|  $$$$$$/|  $$$$$$/|  $$$$$$/|  $$$$$$/
|__/  \__/ \______/  \______/  \______/  \______/ 
]]

function cmds.fetch(...)
    local asciiLines = string.split(kocosAsciiArt, "\n")
    local asciiWidth = 0
    for i=1,#asciiLines do asciiWidth = math.max(asciiWidth, #asciiLines[i]) end

    local spacing = string.rep(" ", 2)

    local data = {}
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

    local function coloriser(color)
        return function(text)
            return "\x1b[" .. color .. "m" .. text .. "\x1b[0m"
        end
    end

    local infoColor = coloriser("38;2;85;85;255")
    local art = coloriser(34)

    table.insert(data, "OS: " .. _OSVERSION)
    table.insert(data, "Kernel: " .. _KVERSION)
    local memUsed = info.memTotal - info.memFree
    table.insert(data, string.format("Memory: %s / %s (%.2f%%)", string.memformat(memUsed), string.memformat(info.memTotal), memUsed / info.memTotal * 100))
    table.insert(data, string.format("Uptime: %s:%s:%s.%s", hours, mins, secs, ms))
    table.insert(data, "Terminal: basicTTY")
    table.insert(data, "Shell: basicTTY")
    table.insert(data, "Boot: " .. info.boot:sub(1, 6) .. "...")
    table.insert(data, "Architecture: " .. info.arch)
    table.insert(data, "Components: " .. #assert(clist(true)))
    table.insert(data, "Threads: " .. info.threadCount)
    table.insert(data, string.format("Battery: %.2f%%", info.energy / info.maxEnergy * 100))

    local kocos = _OS.component.kocos
    if kocos then
        table.insert(data, "VM Name: " .. kocos.getName())
        table.insert(data, "VM Host: " .. kocos.getHost())
        table.insert(data, "VM Hypervisor: " .. kocos.getHypervisor())
        table.insert(data, "Host Kernel: " .. kocos.getKernel())
    end

    do
        local color = ""
        for i=0,7 do
            local dark = 40 + i
            local bright = 100 + i
            color = color .. string.format("\x1b[%dm  \x1b[%dm  \x1b[0m", dark, bright)
        end
        table.insert(data, "Color: " .. color)
    end
    for mountpoint in _K.fs.mountedPartitions() do
        local mountInfo = assert(stat("/" .. mountpoint))
        if mountInfo.total > 0 then
            table.insert(data, string.format("Disk (%s): %s / %s (%.2f%%)", "/" .. mountpoint,
                string.memformat(mountInfo.used), string.memformat(mountInfo.total), mountInfo.used / mountInfo.total * 100))
        end
    end

    if #data > #asciiLines then
        local toPrepend = math.floor((#data - #asciiLines) / 2)
        for i=1,toPrepend do
            table.insert(asciiLines, 1, "")
        end
    end

    local lineCount = math.max(#asciiLines, #data)
    for i=1,lineCount do
        local line = asciiLines[i] or ""
        line = art(line) .. string.rep(" ", asciiWidth - #line)
        if data[i] then
            local colon = string.find(data[i], ":", nil, true)
            local before = string.sub(data[i], 1, colon)
            local after = string.sub(data[i], colon + 1)
            line = line .. spacing .. infoColor(before) .. after
        end
        print(line)
    end
end

function cmds.clear()
    write(stdout, "\x1b[2J")
end

local function parseTerm16(s)
    local t = {
        [":"] = "A",
        [";"] = "B",
        ["<"] = "C",
        ["="] = "D",
        [">"] = "E",
        ["?"] = "F",
    }
    return tonumber(string.gsub(s, ".", t), 16)
end

local escapePattern = "\x1b%[[\x30-\x3F]*[\x20-\x2F]*[\x40-\x7E]"
local paramPattern = "[\x30-\x3F]+"

function cmds.logKeys()
    local lib = unicode or string
    print("Press enter to exit")
    write(stdout, "\x1b[5i") -- Enable immediate keyboard input
    local notExited = true
    while notExited do
        local data, err = read(stdout, math.huge)
        if err then error(err) end
        for escape in string.gmatch(data, escapePattern) do
            local term = escape:sub(-1, -1)
            local param = string.match(escape, paramPattern)
            local n = parseTerm16(param)
            local mod = n % 16
            n = math.floor(n / 16)
            if term == "|" then
                printf("Pressed 0x%02x %s", n, lib.char(n))
            elseif term == "\\" then
                printf("Pressed scancode 0x%02x", n)
                if n == 0x1C then notExited = false break end
            end
        end
        coroutine.yield()
    end
    write(stdout, "\x1b[4i") -- Keyboard be gone
end

function cmds.unreliable(...)
    local args, opts = parse(...)
    local odds = tonumber(args[1]) or 30
    odds = odds / 100
    local spread = tonumber(args[2]) or 15
    spread = spread / 100
    local visited = {}
    local function makeUnreliable(t)
        if visited[t] then return end
        visited[t] = true
        for k, v in pairs(t) do
            if type(v) == "function" and math.random() < spread then
                t[k] = function(...)
                    if math.random() < odds then
                        error("unreliable")
                    end
                    return v(...)
                end
            -- TTY is safe because it just destroys this program if it breaks
            elseif type(v) == "table" then
                makeUnreliable(v)
            end
        end
    end
    -- Simulate extremely buggy kernel
    makeUnreliable(_K.syscalls)
    makeUnreliable(_K.event)
    makeUnreliable(_K.network)
    makeUnreliable(_K.process)
    makeUnreliable(_K.auth)
end

function cmds.bsod()
    _K.process = nil
end

function cmds.run(args)
    local cmd = table.remove(args, 1)
    local err, pid = syscall("pspawn", cmd, {
        args = args,
        fdMap = {
            [0] = stdout,
            [1] = stdin,
            [2] = stdout,
        },
    })
    if err then error(err) end
    syscall("pawait", pid)
    syscall("pexit", pid)
end

function cmds.radiocat(args)
    local p = tonumber(args[1]) or 1
    _K.radio.open(p)
    while true do
        if _K.event.queued(_K.radio.RADIO_EVENT) then
            local _, sender, port, data, distance = _K.event.pop(_K.radio.RADIO_EVENT)
            printf("%s:%d (%.2fm) > %s)", sender, port, distance, data)
        end
        coroutine.yield()
    end
end

function cmds.radiosend(args)
    local addr = args[1]
    local port = tonumber(args[2])
    local data = args[3]
    assert(_K.radio.send(addr, port, data))
end

do
-- Taken from https://gist.github.com/kymckay/25758d37f8e3872e1636d90ad41fe2ed
--[[
    Implemented as described here:
    http://flafla2.github.io/2014/08/09/perlinnoise.html
]]--

perlin = {}
perlin.p = {}

-- Hash lookup table as defined by Ken Perlin
-- This is a randomly arranged array of all numbers from 0-255 inclusive
local permutation = {151,160,137,91,90,15,
  131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
  190, 6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,
  88,237,149,56,87,174,20,125,136,171,168, 68,175,74,165,71,134,139,48,27,166,
  77,146,158,231,83,111,229,122,60,211,133,230,220,105,92,41,55,46,245,40,244,
  102,143,54, 65,25,63,161, 1,216,80,73,209,76,132,187,208, 89,18,169,200,196,
  135,130,116,188,159,86,164,100,109,198,173,186, 3,64,52,217,226,250,124,123,
  5,202,38,147,118,126,255,82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,
  223,183,170,213,119,248,152, 2,44,154,163, 70,221,153,101,155,167, 43,172,9,
  129,22,39,253, 19,98,108,110,79,113,224,232,178,185, 112,104,218,246,97,228,
  251,34,242,193,238,210,144,12,191,179,162,241, 81,51,145,235,249,14,239,107,
  49,192,214, 31,181,199,106,157,184, 84,204,176,115,121,50,45,127, 4,150,254,
  138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,66,215,61,156,180
}

-- p is used to hash unit cube coordinates to [0, 255]
for i=0,255 do
    -- Convert to 0 based index table
    perlin.p[i] = permutation[i+1]
    -- Repeat the array to avoid buffer overflow in hash function
    perlin.p[i+256] = permutation[i+1]
end

-- Return range: [-1, 1]
function perlin:noise(x, y, z)
    y = y or 0
    z = z or 0

    -- Calculate the "unit cube" that the point asked will be located in
    local xi = bit32.band(math.floor(x),255)
    local yi = bit32.band(math.floor(y),255)
    local zi = bit32.band(math.floor(z),255)

    -- Next we calculate the location (from 0 to 1) in that cube
    x = x - math.floor(x)
    y = y - math.floor(y)
    z = z - math.floor(z)

    -- We also fade the location to smooth the result
    local u = self.fade(x)
    local v = self.fade(y)
    local w = self.fade(z)

    -- Hash all 8 unit cube coordinates surrounding input coordinate
    local p = self.p
    local A, AA, AB, AAA, ABA, AAB, ABB, B, BA, BB, BAA, BBA, BAB, BBB
    A   = p[xi  ] + yi
    AA  = p[A   ] + zi
    AB  = p[A+1 ] + zi
    AAA = p[ AA ]
    ABA = p[ AB ]
    AAB = p[ AA+1 ]
    ABB = p[ AB+1 ]

    B   = p[xi+1] + yi
    BA  = p[B   ] + zi
    BB  = p[B+1 ] + zi
    BAA = p[ BA ]
    BBA = p[ BB ]
    BAB = p[ BA+1 ]
    BBB = p[ BB+1 ]

    -- Take the weighted average between all 8 unit cube coordinates
    return self.lerp(w,
        self.lerp(v,
            self.lerp(u,
                self:grad(AAA,x,y,z),
                self:grad(BAA,x-1,y,z)
            ),
            self.lerp(u,
                self:grad(ABA,x,y-1,z),
                self:grad(BBA,x-1,y-1,z)
            )
        ),
        self.lerp(v,
            self.lerp(u,
                self:grad(AAB,x,y,z-1), self:grad(BAB,x-1,y,z-1)
            ),
            self.lerp(u,
                self:grad(ABB,x,y-1,z-1), self:grad(BBB,x-1,y-1,z-1)
            )
        )
    )
end

-- Gradient function finds dot product between pseudorandom gradient vector
-- and the vector from input coordinate to a unit cube vertex
perlin.dot_product = {
    [0x0]=function(x,y,z) return  x + y end,
    [0x1]=function(x,y,z) return -x + y end,
    [0x2]=function(x,y,z) return  x - y end,
    [0x3]=function(x,y,z) return -x - y end,
    [0x4]=function(x,y,z) return  x + z end,
    [0x5]=function(x,y,z) return -x + z end,
    [0x6]=function(x,y,z) return  x - z end,
    [0x7]=function(x,y,z) return -x - z end,
    [0x8]=function(x,y,z) return  y + z end,
    [0x9]=function(x,y,z) return -y + z end,
    [0xA]=function(x,y,z) return  y - z end,
    [0xB]=function(x,y,z) return -y - z end,
    [0xC]=function(x,y,z) return  y + x end,
    [0xD]=function(x,y,z) return -y + z end,
    [0xE]=function(x,y,z) return  y - x end,
    [0xF]=function(x,y,z) return -y - z end
}
function perlin:grad(hash, x, y, z)
    return self.dot_product[bit32.band(hash,0xF)](x,y,z)
end

-- Fade function is used to smooth final output
function perlin.fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

function perlin.lerp(t, a, b)
    return a + t * (b - a)
end
end

function cmds.hologramTest(...)
    local args, opts = parse(...)

    local test = args[1] or "minecraft"
    local scale = tonumber(args[2]) or 1

    local l = assert(clist())
    local hologramAddr
    for _, addr in ipairs(l) do
        if ctype(addr) == "hologram" then
            hologramAddr = addr
        end
    end
    assert(hologramAddr, "no hologram found")
    local hologram = assert(cproxy(hologramAddr))

    if test == "minecraft" then
        local seed = os.time()
        local brown = 1
        local green = 2
        local gray = 3

        hologram.setTranslation(0, 0, 0)
        hologram.setPaletteColor(brown, 0x523214)
        hologram.setPaletteColor(green, 0x1e701e)
        hologram.setPaletteColor(gray, 0x403e3a)
        hologram.setScale(scale)
        hologram.clear()
        local w, top, h = hologram.getDimensions()
        printf("Hologram Dimensions: %d x %d x %d", w, top, h)
        local stoneHeight = 10
        local dirtMin, dirtMax = 3, top - stoneHeight - 6

        local function placeTree(x, y, z)
            -- TODO: finish it
            local bh = 3
            hologram.fill(x, z, y, y + bh, brown)
            for ox=-2,2 do
                for oy=-2,2 do
                    local th = 3
                    local d = math.min(math.abs(ox), math.abs(oy))
                    if d < 1 then th = th + 1 end
                    hologram.fill(x + ox, z + oy, y + bh + 1, y + bh + th, green)
                end
            end
        end

        local noiseScale = 1
        local posScale = 10

        for x=1,w do
            for z=1,h do
                local noise = (perlin:noise(x/posScale, seed, z/posScale)/noiseScale+1)/2
                local dirtHeight = math.floor(dirtMin + noise * (dirtMax - dirtMin))
                hologram.fill(x, z, stoneHeight, gray)
                hologram.fill(x, z, stoneHeight+1, stoneHeight+dirtHeight, brown)
                hologram.set(x, stoneHeight+dirtHeight+1, z, green)
                if math.random() < 0.0025 then
                    placeTree(x, stoneHeight+dirtHeight+2, z)
                end
            end
        end
    elseif test == "automata" then
        local w, h, d = hologram.getDimensions()
        hologram.clear()
        hologram.setTranslation(0, 0, 0)
        hologram.setPaletteColor(1, 0x27698a)

        local function cellIndex(x, y)
            x = x - 1
            y = y - 1
            x = x % w
            y = y % d
            return x * d + y
        end

        local grid = {}
        local counts = {}

        local function getCell(x, y)
            return grid[cellIndex(x, y)] or false
        end

        local function setCell(x, y, value)
            grid[cellIndex(x, y)] = value
        end

        local function countNeighbours(x, y)
            local c = 0
            for ox=-1,1 do
                for oy=-1,1 do
                    if ox ~= 0 or oy ~= 0 then
                        if getCell(x+ox, y+oy) then
                            c = c + 1
                        end
                    end
                end
            end
            return c
        end

        for x=4,w-4 do
            for y=4,d-4 do
                local v = math.random() < 0.5
                setCell(x, y, v)
                if v then hologram.set(x, 1, y, true) end
            end
        end

        local duration = 10
        local start = _OS.computer.uptime()
        local finish = start + duration
        while true do
            if _OS.computer.uptime() >= finish then break end
            for x=1,w do
                for y=1,d do
                    local ci = cellIndex(x, y)
                    counts[ci] = countNeighbours(x, y)
                end
            end
            for x=1,w do
                for y=1,d do
                    local ci = cellIndex(x, y)
                    local current = getCell(x, y)
                    local count = counts[ci]
                    local nextState = current
                    if current then
                        if count < 2 or count > 3 then
                            nextState = false
                        end
                    else
                        if count == 3 then
                            nextState = true
                        end
                    end
                    setCell(x, y, nextState)
                    if current ~= nextState then hologram.set(x, 1, y, nextState) end
                end
            end
        end
    elseif test == "solar" then
        local w, h, d = hologram.getDimensions()
        hologram.setPaletteColor(1, 0xe3da27)
        hologram.setPaletteColor(2, 0x999993)
        hologram.clear()
        local function drawSphere(x, y, z, r, c)
            for ox=-r,r do
                for oy=-r,r do
                    if ox^2 + oy^2 <= r^2 then
                        local h = math.floor(math.sqrt(r^2 - ox ^ 2 - oy ^ 2))
                        hologram.fill(x + ox, z + oy, y - h, y + h, c)
                    end
                end
            end
        end
        drawSphere(w/2,h/2,d/2,6,1)
        local duration = 20
        local start = _OS.computer.uptime()
        local finish = start + duration
        local dist = 13
        local angle = 0
        while true do
            if _OS.computer.uptime() >= finish then break end
            local cx, cy, cz = w/2,h/2,d/2
            local ox,oz = math.cos(angle)*dist, math.sin(angle)*dist
            local r = 3
            drawSphere(cx+ox, cy, cz+oz, r, false)
            angle = angle + 0.2

            ox,oz = math.cos(angle)*dist, math.sin(angle)*dist
            drawSphere(cx+ox, cy, cz+oz, r, 2)
            coroutine.yield(0.1)
        end
    elseif test == "clear" then
        hologram.clear()
    end
end

local function hex(bin)
    local hexStr = "0123456789ABCDEF"
    local s=""
    for i=1,#bin do
        local b = bin:byte(i, i)
        local h = math.floor(b/16)
        local l = b%16

        s = s .. hexStr:sub(h+1,h+1) .. hexStr:sub(l+1,l+1)
    end
    return s
end

local function readFile(path)
    local f = assert(open(path, "r"))
    local data = ""
    while true do
        local chunk, err = read(f, math.huge)
        if err then assert(close(f)) error(err) end
        if not chunk then break end
        data = data .. chunk
    end
    assert(close(f))
    return data
end

local function writeToFile(path, data)
    if ftype(path) == "missing" then
        assert(touch(path, 2^16-1))
    end
    local f = assert(open(path, "w"))
    assert(write(f, data))
    assert(close(f))
end

function cmds.data(args)
    local _, dataAddr = syscall("cprimary", "data")
    assert(dataAddr, "no data card found")
    local data = assert(cproxy(dataAddr))
    if args[1] == "limit" then
        print(string.memformat(data.getLimit()))
    elseif args[1] == "crc32" then
        print(hex(data.crc32(readFile(args[2]))))
    elseif args[1] == "md5" then
        print(hex(data.md5(readFile(args[2]))))
    elseif args[1] == "sha256" then
        print(hex(data.sha256(readFile(args[2]))))
    elseif args[1] == "deflate" then
        local fdata = readFile(args[2])
        local deflated = data.deflate(fdata)
        writeToFile(args[3], deflated)
    elseif args[1] == "inflate" then
        local fdata = readFile(args[2])
        local inflated = data.inflate(fdata)
        writeToFile(args[3], inflated)
    else
        print("Unknown operation: " .. args[1])
    end
end

local function logger()
    local s = assert(socket("domain", "channel"))
    assert(serve(s, {port = "log_server"}))
    while true do
        -- This is btw HORRIBLY bad
        -- Because if the client errors out
        -- Since its from our process
        -- And the sockets get leaked
        -- The server hangs
        -- Whoopsies
        local c = assert(accept(s))
        KOCOS.log("[LOGGER] Client connected")
        while true do
            local msg, err = read(c, math.huge)
            if err then KOCOS.log("Client error: %s", err) break end
            if not msg then break end
            KOCOS.log("[LOGGER] From client: %s", msg)
            assert(write(c, msg))
            coroutine.yield()
        end
        assert(close(c))
        coroutine.yield()
    end
end

function cmds.logger()
    assert(attach(logger, "logger"))
    print("Logger started")
end

function cmds.log(args)
    local msg = table.concat(args, " ")
    local s = assert(socket("domain", "channel"))
    assert(connect(s, "log_server"))
    print("Connected")
    assert(write(s, msg))
    print("Sent")
    assert(msg == assert(read(s, math.huge)), "bad response") -- block until they write back
    print("Confirmation received")
    assert(close(s))
    print("Closed")
end

function cmds.hostname(...)
    local args, opts = parse(...)
    local name = args[1]
    local e, n = syscall("hostname", name)
    assert(n, e)
    print(n)
end

function cmds.sleep(...)
    local args, opts = parse(...)
    coroutine.yield(tonumber(args[1]))
end

local function pspawn(init, conf)
    local err, pid = syscall("pspawn", init, conf)
    return pid, err
end

function cmds.lua(args)
    local pid = assert(pspawn("/luart", {
        -- this is such an epic banger idea
        args = args,
        fdMap = {
            [0] = stdout,
            [1] = stdin,
            [2] = stdout,
        },
    }))
    syscall("pawait", pid)
    syscall("pexit", pid)
end

function cmds.ptree()
    local function printTree(pid, depth)
        depth = depth or 0
        local indentation = string.rep("\t", depth)
        local info = assert(pinfo(pid))
        print(indentation .. info.cmdline)
        print(indentation .. info.ring)
        for _, child in ipairs(info.children) do
            printTree(child, depth + 1)
        end
    end

    local err, tree = syscall("pself")
    assert(tree, err)
    printTree(tree)
end

function cmds.plist()
    local pid
    while true do
        pid = pnext(pid)
        if not pid then break end
        local info = assert(pinfo(pid))
        print(pid, info.cmdline, table.concat(info.args, " "))
    end
end

function cmds.time(args)
    local cmd = table.remove(args, 1)
    assert(cmds[cmd], "unknown command")
    local start = _OS.computer.uptime()
    cmds[cmd](args)
    printf("Took %.2fs", _OS.computer.uptime() - start)
end

function cmds.rebindTest()
    close(stdout)
    local gpu = _OS.component.gpu.address

    local screens = {}
    for addr in _OS.component.list("screen") do
        table.insert(screens, addr)
    end

    for _, screen in ipairs(screens) do
        local keyboards = _OS.component.invoke(screen, "getKeyboards")
        local keyboard = keyboards[1] or "no keyboard"

        local t = ttyopen(gpu, keyboard, {boundTo = screen})

        attach(function()
            write(t, "\x1b[2J")
            while true do
                write(t, "Input: ")
                local line = read(t, math.huge)
                write(t, line .. "\n")
                coroutine.yield()
            end
        end, "rebind-" .. screen)
    end
    while true do coroutine.yield() end
end

-- We don't support *changing* resolution rn so...
function cmds.resolution(args)
    write(stdout, "\x1b[5n")
    local back = read(stdin, math.huge)

    local _, _, w, h = string.find(back, "(%d+);(%d+)")
    printf("%s x %s", w or "unknown", h or "unknown")
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
        local pi = assert(pinfo())
        local uid = pi.uid
        local _, uinfo = syscall("uinfo", uid)
        local _, hostname = syscall("hostname")
        write(stdout, string.format("\x1b[0m\x1b[32m%s\x1b[0m@\x1b[96m%s \x1b[34m> \x1b[0m", uinfo.name, hostname))
        local line = readLine()

        -- Basic program that traverses filesystem
        local parts = string.split(line, " ")

        local cmd = parts[1] or ""
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

attach(myBeloved, "command")

while true do
    coroutine.yield()
end
