local rootfs = computer.getBootAddress()

KOCOS_CONFIG = {
    rootfs = rootfs,
}

-- Will be overwritten by KOCOS anyways
function dofile(file, ...)
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

dofile("kernel.lua")

local tty = KOCOS.tty.create(component.gpu, component.screen)
tty:clear()

KOCOS.log("Main OS boot")

local printingLogsProcess = assert(KOCOS.process.spawn())
printingLogsProcess:attach(function()
    while true do
        if KOCOS.event.queued("klog") then
            local _, msg, time = KOCOS.event.pop("klog")
            tty:print("[%3.2f] %s\n", time, msg)
        end
        coroutine.yield()
    end
end)
KOCOS.log("Created log process")

printingLogsProcess.events.listen(KOCOS.logAll)

while true do
    KOCOS.runDeferred(0.1)
    KOCOS.event.process(0.05)
    KOCOS.process.run()
end
