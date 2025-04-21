local libs = {...}

---@class Build.LibInfo
---@field directory string
--- Module to files
---@field modules {[string]: string}
---@field libs string[]

---@type {[string]: Build.LibInfo}
local buildInfo = {
    liblua = {
        directory = "lib/liblua",
        libs = {},
        modules = {
            syscalls = "syscalls.lua",
            lon = "lon.lua",
            io = "io.lua",
            os = "os.lua",
            base = "base.lua",
            -- _start is the entry symbol
            _start = "package.lua",
        },
    },
    libkelp = {
        directory = "lib/libkelp",
        libs = {},
        modules = {
            kelp = "kelp.lua",
        },
    },
}

if #libs == 0 then
    for lib in pairs(buildInfo) do
        table.insert(libs, lib)
    end
end

local luac = "lua tools/luac.lua"
local ld = "lua tools/ld.lua"

local function runCmd(...)
    local cmd = table.concat({...}, " ")
    print(cmd)
    if not os.execute(cmd) then
        error("Command failed")
    end
end

---@param lib Build.LibInfo
local function buildLib(lib)
    local dir = lib.directory

    local linkLibsArgs = {}
    for _, l in ipairs(lib.libs) do
        table.insert(linkLibsArgs, "-l" .. l)
    end

    local linkLibs = table.concat(linkLibsArgs, " ")

    local objs = {}

    for module, file in pairs(lib.modules) do
        local obj = dir .. "/" .. module .. ".o"
        table.insert(objs, obj)
        runCmd(luac, "-m", module, dir .. "/" .. file, "-o", obj, linkLibs)
    end

    local objsStr = table.concat(objs, " ")
    local out = dir .. ".so"

    runCmd(ld, "-o", out, objsStr)
end

for i=1,#libs do
    local lib = libs[i]
    local info = buildInfo[lib]
    assert(info, "unknown lib: " .. lib)
    print("Compiling " .. lib .. "...")
    buildLib(info)
    print("Finished compiling " .. lib)
end
