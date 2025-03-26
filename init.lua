local rootfs = computer.getBootAddress()

local config = {
    rootfs = rootfs,
    init = "/basicTTY.lua",
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

dofile("kernel.lua", config)

local tty = KOCOS.tty.create(component.gpu, component.screen)
tty:clear()

KOCOS.log("Main OS boot")


_G.printingLogsProcess = assert(KOCOS.process.spawn(nil, {
    cmdline = "OS:logproc",
}))
printingLogsProcess:attach(function()
    while true do
        local didSmth = false
        if KOCOS.event.queued("klog") then
            local _, msg, time = KOCOS.event.pop("klog")
            tty:print("[LOG   %3.2f] %s\n", time, msg)
            didSmth = true
        end
        if KOCOS.event.queued("kpanic") then
            local _, msg, time = KOCOS.event.pop("kpanic")
            tty:print("[PANIC %3.2f] %s\n", time, msg)
            didSmth = true
        end
        if not (didSmth or KOCOS.hasDeferred()) then
            computer.beep()
            KOCOS.process.kill(_G.printingLogsProcess)
            break
        end
        coroutine.yield()
    end
end)
KOCOS.log("Created log process")

KOCOS.defer(function()
    KOCOS.log("Finished boot")
end, -math.huge)

KOCOS.loop()
