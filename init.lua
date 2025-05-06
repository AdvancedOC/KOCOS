local rootfs = computer.getBootAddress()

_OSVERSION = "KOCOS Demo"

local config = {
    rootfs = rootfs,
    init = "/basicTTY.lua",
}

-- Will be overwritten by KOCOS anyways
local function dofile(file, ...)
    local root = component.proxy(rootfs)
    local f = assert(root.open(file, "r"))

    local code = ""
    while true do
        local data, err = root.read(f, math.huge)
        if err then error(err) end
        if not data then break end
        code = code .. data
    end

    root.close(f)

    return assert(load(code, "=" .. file, "bt", _G))(...)
end

dofile("kernel.lua", config)
