---@alias KOCOS.FileSystemDriver table

---@class KOCOS.File
---@field mode "w"|"r"
---@field refc integer
---@field kind "disk"|"memory"|"pipe"
---@field events KOCOS.EventSystem
-- For disk
---@field fd any
---@field manager KOCOS.FileSystemDriver
-- For memory
---@field buffer string
---@field cursor integer
-- For pipes
---@field output KOCOS.File
---@field input KOCOS.File

local fs = {}

fs.drivers = {}

---@type {[string]: KOCOS.FileSystemDriver}
local globalTranslation = {}

function fs.canonical(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")
    local stack = {}

    for _, part in ipairs(parts) do
        table.insert(stack, part)
        if part == string.rep(".", #part) then
            for _=1,#part do
                stack[#stack] = nil
            end
        end
    end

    return "/" .. table.concat(stack, "/")
end

---@return KOCOS.FileSystemDriver, string
function fs.resolve(path)
    path = fs.canonical(path)
    if path:sub(1, 1) == "/" then path = path:sub(2) end
    local parts = string.split(path, "%/")

    for i=#parts, 1, -1 do
        local subpath = table.concat(parts, "/", 1, i)
        local manager = globalTranslation[subpath]
        if manager then
            return manager, table.concat(parts, "/", i+1)
        end
    end

    return globalTranslation[""], path
end

function fs.addDriver(driver)
    table.insert(fs.drivers, driver)
end

---@return KOCOS.FileSystemDriver?
function fs.driverFor(uuid)
    local drive = component.proxy(uuid)

    for _, driver in ipairs(fs.drivers) do
        local manager = driver.create(drive)
        if manager then return manager end
    end
    return "fuck you"
end

KOCOS.fs = fs

KOCOS.log("Loaded filesystem")

KOCOS.defer(function()
    globalTranslation[""] = assert(fs.driverFor(KOCOS.defaultRoot), "MISSING ROOTFS DRIVER OH NO")
    KOCOS.log("Mounted default root")

    KOCOS.logAll(fs.resolve("/home/user/data/../etc/conf/stuff/.../usr"))
end, 3)
