local KOCOS = _K

while KOCOS.process.byPid(_OS.printingLogsProcess.pid) do
    coroutine.yield()
end

KOCOS.log("test process")

local tty = _K.tty.create(_OS.component.gpu, _OS.component.screen)

tty:clear()

local stdout = KOCOS.fs.mopen("r")
local stdin = KOCOS.fs.mopen("w")

local commandStdinBuffer = ""
local function readLine()
    while true do
        commandStdinBuffer = commandStdinBuffer .. assert(KOCOS.fs.read(stdin, math.huge))
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
        KOCOS.fs.write(stdout, "> ")
        local line = readLine()

        -- Basic program that traverses filesystem

        local t = KOCOS.fs.type(line)

        if t == "file" then
            -- cat
            local f = assert(KOCOS.fs.open(line, "r"))
            local total = 0
            local maximum = 65536
            while true do
                local chunk, err = KOCOS.fs.read(f, 1024)
                if err then error(err) end
                if not chunk then break end
                total = total + #chunk
                if total >= maximum then
                    KOCOS.fs.write(stdout, "...")
                    break
                end
                KOCOS.fs.write(stdout, chunk)
                coroutine.yield()
            end
            KOCOS.fs.close(f)
            KOCOS.fs.write(stdout, "\n")
        elseif t == "directory" then
            -- ls
            local files = assert(KOCOS.fs.list(line))
            for i=1,#files do
                local file = files[i]
                KOCOS.fs.write(stdout, file .. "\n")
            end
        else
            KOCOS.fs.write(stdout, "Error: Not a file\n")
        end

        coroutine.yield()
    end
end

_OS.ttyProcess:attach(myBeloved, "command")

local function isEscape(char)
    return char < 0x20 or (char >= 0x7F and char <= 0x9F)
end

local inputBuffer
while true do
    while stdout.events.queued("write") do
        local data = stdout.buffer
        stdout.buffer = ""
        stdout.cursor = 0
        stdout.events.pop("write")
        tty:write(data)
        coroutine.yield()
    end

    if stdin.events.queued("read") and not inputBuffer then
        inputBuffer = ""
    end

    if inputBuffer then
        local ok, _, char, code = _K.event.pop("key_down")
        if ok then
            local lib = unicode or string
            local backspace = 0x0E
            local enter = 0x1C
            if code == enter then
                stdin.events.clear()
                stdin.buffer = inputBuffer .. "\n"
                stdin.cursor = 0
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
