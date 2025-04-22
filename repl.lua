-- Lua REPL
local sys = require("syscalls")
local lon = require("lon")

local stdout = 0
local stdin = 1
local commandStdinBuffer = ""
local function readLine()
    while true do
        commandStdinBuffer = commandStdinBuffer .. assert(sys.read(stdin, math.huge))
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

sys.write(stdout, _VERSION .. "\n")
sys.write(stdout, "Type exit to exit\n")

local function printExpr(asExpr)
    local r = {asExpr()}
    local encoded = {}
    for i=1,#r do
        encoded[i] = lon.encode(r[i], true)
    end
    if #encoded > 0 then
        sys.write(stdout, table.concat(encoded, ", ") .. "\n")
    end
end

while true do
    sys.write(stdout, "\x1b[34mlua> \x1b[0m")
    local code = readLine()
    if code == "exit" then break end
    if #code > 0 then
        local asExpr = load("return " .. code, "=repl")
        if asExpr then
            local ok, err = xpcall(printExpr, debug.traceback, asExpr)
            if not ok then sys.write(2, err .. "\n") end
        else
            local stmt, err = load(code, "=repl")
            if stmt then
                local ok, err = xpcall(stmt, debug.traceback)
                if not ok then sys.write(2, err .. "\n") end
            else
                sys.write(2, err .. "\n")
            end
        end
    end
    coroutine.yield()
end
