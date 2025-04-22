local rootfs = computer.getBootAddress()

_OSVERSION = "KOCOS Demo"

local config = {
    rootfs = rootfs,
    init = "/basicTTY.lua",
    logThreadEvents = false,
    syscallTraceback = false,
    needsExtensions = true,
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
tty.h = tty.h - 1

KOCOS.log("Main OS boot")


_G.printingLogsProcess = assert(KOCOS.process.spawn(nil, {
    cmdline = "OS:logproc",
}))
printingLogsProcess:attach(function()
    local lastYield = computer.uptime()
    while true do
        local didSmth = false
        if KOCOS.event.queued("klog", "kpanic") then
            local e, msg, time = KOCOS.event.pop("klog", "kpanic")
            if e == "klog" then
                tty:print("[LOG   %3.2f] %s\n", time, msg)
            elseif e == "kpanic" then
                tty:print("[PANIC %3.2f] %s\n", time, msg)
            end
            didSmth = true
        end
        if not (didSmth or KOCOS.hasDeferred()) then
            computer.beep()
            KOCOS.process.kill(_G.printingLogsProcess)
            break
        end
        local w, h = tty.w, tty.h+1
        local total = computer.totalMemory()
        local used = total - computer.freeMemory()
        local info = string.format("Memory: %s / %s (%.2f%%)", string.memformat(used), string.memformat(total), used / total * 100)
        tty.gpu.fill(1, h, w, 1, " ")
        tty.gpu.set(w-#info, h, info)
        local now = computer.uptime()
        local waiting = not KOCOS.event.queued("klog") and not KOCOS.event.queued("kpanic")
        if now - lastYield > 3 or waiting then
            lastYield = now
            coroutine.yield()
        end
    end
end)
KOCOS.log("Created log process")

KOCOS.defer(function()
    KOCOS.log("Finished boot")
end, -math.huge)

KOCOS.loop()
