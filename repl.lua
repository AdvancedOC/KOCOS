-- Lua REPL
local sys = require("syscalls")
local lon = require("lon")
local io = require("io")

print(_VERSION)
print("Pres Ctrl + D (close stdin) to exit")

local function printExpr(asExpr)
    local r = {asExpr()}
    local encoded = {}
    for i=1,#r do
        encoded[i] = lon.encode(r[i], true)
    end
    if #encoded > 0 then
        print(table.concat(encoded, ", "))
    end
end

while true do
    io.write("\x1b[34mlua> \x1b[0m")
    local code = io.read("l")
    if not code then break end
    if #code > 0 then
        local asExpr = load("return " .. code, "=repl")
        if asExpr then
            local ok, err = xpcall(printExpr, debug.traceback, asExpr)
            if not ok then print(err) end
        else
            local stmt, err = load(code, "=repl")
            if stmt then
                local ok, err = xpcall(stmt, debug.traceback)
                if not ok then eprint(err) end
            else
                eprint(err)
            end
        end
    end
    coroutine.yield()
end
