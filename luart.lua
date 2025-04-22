-- LuaRT, the binary that runs Lua files

local file = arg[1] or "/repl.lua"
arg = {table.unpack(arg, 2)}
---@module "lib.liblua.syscalls"
local sys = require("syscalls")
---@module "lib.liblua.io"
local io = require("io")

local f = assert(io.open(file, "r"))
local code = f:read("a")
assert(f:close())

return load(code, "=" .. file)(table.unpack(arg))
