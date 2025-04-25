-- KOCOS Virtual Machines
-- Literally peak

---@class KOCOS.VComponent
---@field type string
---@field slot integer
---@field methods {[string]:function}
---@field docs {[string]:string}
---@field close fun()
---@field internal table

---@class KOCOS.KVM
---@field address string
---@field name string
---@field instance thread
---@field namespace _G
---@field components {[string]: KOCOS.VComponent}
---@field tmpAddr? string
---@field mode "running"|"halted"|"restart"
---@field users string[]
---@field signals KOCOS.EventSystem
---@field uptimeOffset number
---Event -> listener
---@field eventsListened {[string]: string}

local kvm = {}

kvm.uuid = KOCOS.testing.uuid

---@param vm KOCOS.KVM
function kvm.init(vm)
    local env = vm.namespace

    env._G = env
    env._VERSION = _VERSION
    env.assert = assert
    env.error = error
    env.getmetatable = getmetatable
    env.ipairs = ipairs
    env.load = function(chunk, name, kind, e)
        return load(chunk, name, kind, e or env)
    end
    env.next = next
    env.pairs = pairs
    env.pcall = pcall
    env.xpcall = xpcall
    env.rawequal = rawequal
    env.rawget = rawget
    env.rawlen = rawlen
    env.rawset = rawset
    env.select = select
    env.setmetatable = setmetatable
    env.tonumber = tonumber
    env.tostring = tostring
    env.type = type
    env.bit32 = table.copy(bit32)
    env.coroutine = table.copy(coroutine)
    env.debug = table.copy(debug)
    env.math = table.copy(math)
    env.os = table.copy(os)
    env.string = table.copy(string)
    env.table = table.copy(table)
    env.checkArg = checkArg

    local component = {}

    env.component = component

    local computer = {}

    env.computer = computer

    env.unicode = table.copy(unicode)

    vm.instance = coroutine.create(function()
        vm.signals.clear()
        local eeprom = component.list("eeprom")()
        assert(eeprom, "missing eeprom")

        local code = component.invoke(eeprom, "get")
        return load(code, "=" .. vm.name, nil, env)()
    end)


    -- Stuff that needs VM
    function computer.address()
        return vm.address
    end

    function computer.addUser(user)
        checkArg(1, user, "string")
        for i=1,#vm.users do
            if vm.users[i] == user then return end -- no dupes
        end
        table.insert(vm.users, user)
    end

    computer.beep = _G.computer.beep
    computer.energy = _G.computer.energy
    computer.freeMemory = _G.computer.freeMemory

    function computer.getArchitectures()
        return {_VERSION}
    end

    computer.getArchitecture = _G.computer.getArchitecture

    function computer.getDeviceInfo()
        return {}
    end

    function computer.isRobot()
        -- TODO: allow virtual robots
        return false
    end

    computer.maxEnergy = _G.computer.maxEnergy

    function computer.removeUser(user)
        checkArg(1, user, "string")
        for i=1,#vm.users do
            if vm.users[i] == user then
                table.remove(vm.users, user)
                break
            end
        end
    end

    function computer.setArchitecture(arch)
        checkArg(1, arch, "string")
        if arch ~= _VERSION then
            error("unsupported architecture")
        end
    end

    function computer.shutdown(reboot)
        vm.mode = reboot and "restart" or "halted"
        KOCOS.yield()
    end

    function computer.tmpAddress()
        return vm.tmpAddr
    end

    computer.totalMemory = _G.computer.totalMemory
    computer.getProgramLocations = _G.computer.getProgramLocations

    function computer.uptime()
        return _G.computer.uptime() - vm.uptimeOffset
    end

    function computer.users()
        return table.unpack(vm.users)
    end

    function computer.pullSignal()
        KOCOS.yield() -- we still always yield
        return vm.signals.pop()
    end

    function computer.pushSignal(name, ...)
        vm.signals.push(name, ...)
    end

    function component.doc(comp, method)
        checkArg(1, comp, "string")
        checkArg(2, method, "string")
        if not vm.components[comp] then return end
        return vm.components[comp].docs[method]
    end

    function component.fields(comp)
        checkArg(1, comp, "string")
        return {}
    end

    function component.invoke(comp, method, ...)
        checkArg(1, comp, "string")
        local c = vm.components[comp]
        assert(c, "no such component")
        assert(c.methods[method], "no such method")
        return c.methods[method](...)
    end

    function component.list(type, exact)
        local t = {}

        for comp, c in pairs(vm.components) do
            if type then
                if exact then
                    if c.type == type then
                        t[comp] = c.type
                    end
                elseif string.match(c.type, type) then
                    t[comp] = c.type
                end
            else
                t[comp] = c.type
            end
        end

        local key = nil
        setmetatable(t, {__call = function()
            key = next(t, key)
            if key then return key, t[key] end
        end})

        return t
    end

    function component.methods(comp)
        checkArg(1, comp, "string")
        local c = vm.components[comp]
        assert(c, "no such component")
        local methods = {}
        for k, _ in pairs(c.methods) do
            methods[k] = true
        end
        return methods
    end

    local proxyMeta = {
        __pairs = function(self)
            local keyProxy, keyField, value
            return function()
              if not keyField then
                repeat
                  keyProxy, value = next(self, keyProxy)
                until not keyProxy or keyProxy ~= "fields"
              end
              if not keyProxy then
                keyField, value = next(self.fields, keyField)
              end
              return keyProxy or keyField, value
            end
        end,
    }

    local componentCallback = {
        __call = function(self, ...)
            return component.invoke(self.address, self.name, ...)
        end,
        __tostring = function(self)
            return component.doc(self.address, self.name) or "function"
        end
    }

    function component.proxy(comp)
        checkArg(1, comp, "string")
        local c = vm.components[comp]
        assert(c, "no such component")
        local t = component.type(comp)
        local s = component.slot(comp)

        local proxy = {address = comp, type = t, slot = s, fields = {}}
        local methods = component.methods(comp)
        for method in pairs(methods) do
            proxy[method] = setmetatable({address=comp,name=method}, componentCallback)
        end
        return setmetatable(proxy, proxyMeta)
    end

    function component.slot(comp)
        checkArg(1, comp, "string")
        local c = vm.components[comp]
        assert(c, "no such component")
        return c.slot
    end

    function component.type(comp)
        checkArg(1, comp, "string")
        local c = vm.components[comp]
        assert(c, "no such component")
        return c.type
    end

    return vm

end

---@param vmName string
function kvm.open(vmName)
    local addr = kvm.uuid()
    vmName = vmName or ("kvm-" .. addr)

    ---@type KOCOS.KVM
    local vm = {
        address = addr,
        name = vmName,
        instance = coroutine.create(function()
            error("Uninitialized")
        end),
        eventsListened = {},
        components = {},
        namespace = {},
        mode = "running",
        tmpAddr = nil,
        users = {},
        signals = KOCOS.event.create(KOCOS.maxEventBacklog),
        uptimeOffset = computer.uptime(),
    }

    kvm.init(vm)

    return vm
end

---@param vm KOCOS.KVM
function kvm.resume(vm)
    return KOCOS.resume(vm.instance)
end

---@param vm KOCOS.KVM
---@param component KOCOS.VComponent
---@param addr? string
function kvm.add(vm, component, addr)
    addr = addr or kvm.uuid()
    vm.components[addr] = component
    return addr
end

---@param vm KOCOS.KVM
function kvm.passthrough(vm, address, raddr)
    local methods = component.methods(address)
    ---@type KOCOS.VComponent
    local vcomp = {
        type = component.type(address),
        slot = component.slot(address),
        methods = {},
        docs = {},
        internal = {},
        close = function() end,
    }
    for k in pairs(methods) do
        vcomp.methods[k] = function(...)
            return component.invoke(address, k, ...)
        end
        vcomp.docs[k] = component.doc(address, k)
    end
    return kvm.add(vm, vcomp, raddr)
end

---@param vm KOCOS.KVM
function kvm.remove(vm, component)
    if vm.components[component] then
        vm.components[component].close()
    end
    vm.components[component] = nil
    return true
end

---@param vm KOCOS.KVM
function kvm.close(vm)
    KOCOS.log("Closing VM: %s", vm.name)
    while true do
        local c = next(vm.components)
        if not c then break end
        -- calls destructors on all components
        kvm.remove(vm, c)
    end
end

---@param vm KOCOS.KVM
---@param slot? integer
-- Generic Virtual GPU
-- Palettes are completely unsupported currently
-- So are VRAM buffers
function kvm.addVGPU(vm, slot)
    ---@type string?
    local screen
    ---@return table
    local function getScreenFuncs()
        local c = assert(vm.components[screen], "not bound to screen")
        return c.internal.vgpu
    end
    return kvm.add(vm, {
        type = "gpu",
        slot = slot or -1,
        close = function() end,
        docs = {},
        methods = {
            ---@param address string
            ---@param reset? boolean
            bind = function(address, reset)
                reset = KOCOS.default(reset, true)
                local c = assert(vm.components[address], "no such component")
                local vgpu = assert(c.internal.vgpu, "incompatible")
                if reset then vgpu.reset() end
                return true
            end,
            getScreen = function()
                if not vm.components[screen] then screen = nil end
                return screen
            end,
            getBackground = function()
                local vgpu = getScreenFuncs()
                return vgpu.getBackground(), false
            end,
            setBackground = function(color, isPaletteIndex)
                checkArg(1, color, "number")
                assert(not isPaletteIndex, "palettes are unsupported")
                local vgpu = getScreenFuncs()
                local old = vgpu.getBackground()
                vgpu.setBackground(color)
                return old
            end,
            getForeground = function()
                local vgpu = getScreenFuncs()
                return vgpu.getForeground(), false
            end,
            setForeground = function(color, isPaletteIndex)
                checkArg(1, color, "number")
                assert(not isPaletteIndex, "palettes are unsupported")
                local vgpu = getScreenFuncs()
                local old = vgpu.getForeground()
                vgpu.setForeground(color)
                return old
            end,
            maxDepth = function()
                return getScreenFuncs().maxDepth()
            end,
            getDepth = function()
                return getScreenFuncs().getDepth()
            end,
            setDepth = function(depth)
                checkArg(1, depth, "number")
                local vgpu = getScreenFuncs()
                local old = vgpu.getDepth()
                vgpu.setDepth(depth)
                local t = {
                    [1] = "OneBit",
                    [4] = "FourBit",
                    [8] = "EightBit",
                }
                return t[old] or "OtherBit"
            end,
            maxResolution = function()
                return getScreenFuncs().maxResolution()
            end,
            getResolution = function()
                return getScreenFuncs().getResolution()
            end,
            setResolution = function(w, h)
                checkArg(1, w, "number")
                checkArg(2, h, "number")
                getScreenFuncs().setResolution(w, h)
                return true
            end,
            getViewport = function()
                return getScreenFuncs().getResolution()
            end,
            setViewport = function(w, h)
                checkArg(1, w, "number")
                checkArg(2, h, "number")
                getScreenFuncs().setResolution(w, h)
                return true
            end,
            get = function(x, y)
                checkArg(1, x, "number")
                checkArg(2, y, "number")
                return getScreenFuncs().get(x, y)
            end,
            set = function(x, y, value, vertical)
                checkArg(1, x, "number")
                checkArg(2, y, "number")
                checkArg(3, value, "string")
                checkArg(4, vertical, "boolean", "nil")
                return getScreenFuncs().set(x, y, value, vertical)
            end,
            copy = function(x, y, w, h, tx, ty)
                checkArg(1, x, "number")
                checkArg(2, y, "number")
                checkArg(3, w, "number")
                checkArg(4, h, "number")
                checkArg(5, tx, "number")
                checkArg(6, ty, "number")
                return getScreenFuncs().copy(x, y, w, h, tx, ty)
            end,
            fill = function(x, y, w, h, c)
                checkArg(1, x, "number")
                checkArg(2, y, "number")
                checkArg(3, w, "number")
                checkArg(4, h, "number")
                checkArg(5, c, "string")
                return getScreenFuncs().fill(x, y, w, h, c)
            end,
        },
        internal = {},
    })
end

---@param vm KOCOS.KVM
---@param code string
---@param data string
---@param label? string
function kvm.addBIOS(vm, code, data, label)
    -- This EEPROM reports that it has 4KiB of code and 1KiB data, but actually allows any amount
    return kvm.add(vm, {
        type = "eeprom",
        slot = 0,
        internal = {},
        close = function() end,
        docs = {},
        methods = {
            get = function()
                return code
            end,
            set = function(newCode)
                code = newCode
                return true
            end,
            getData = function()
                return data
            end,
            setData = function(newData)
                data = newData
            end,
            getSize = function()
                return 4096
            end,
            getDataSize = function()
                return 1024
            end,
            getChecksum = function()
                return "junkchck"
            end,
            makeReadonly = function(chck)
                error("unsupported")
            end,
            getLabel = function()
                return label
            end,
            setLabel = function(newLabel)
                label = newLabel
                return true
            end,
        },
    })
end

---@param vm KOCOS.KVM
---@param event string
function kvm.listen(vm, event)
    if vm.eventsListened[event] then return end
    local handler = KOCOS.event.listen(function(e, ...)
        if e == event then
            vm.signals.push(e, ...)
        end
    end)
    vm.eventsListened[event] = handler
end

---@param vm KOCOS.KVM
---@param event string
function kvm.forget(vm, event)
    local handler = vm.eventsListened[event]
    vm.eventsListened[event] = nil
    KOCOS.event.forget(handler)
end

---@type {[string]:fun(proc: KOCOS.Process, vm: KOCOS.KVM, ...): ...}
kvm.ioctl = {}

function kvm.ioctl.add(proc, vm, vcomp)
    return kvm.add(vm, vcomp)
end

function kvm.ioctl.addVGPU(proc, vm, slot)
    return kvm.addVGPU(vm, slot)
end

function kvm.ioctl.addBIOS(proc, vm, code, data, label)
    checkArg(1, code, "string")
    checkArg(2, data, "string")
    checkArg(3, label, "string", "nil")
    return kvm.addBIOS(vm, code, data, label)
end

function kvm.ioctl.pass(proc, vm, addr)
    if component.ringFor(addr) < proc.ring then
        error("permission denied")
    end
    return kvm.passthrough(vm, addr, addr)
end

function kvm.ioctl.tmp(proc, vm, addr)
    checkArg(1, addr, "string", "nil")
    vm.tmpAddr = addr or vm.tmpAddr
    return vm.tmpAddr
end

function kvm.ioctl.remove(proc, vm, component)
    checkArg(1, component, "string")
    return kvm.remove(vm, component)
end

function kvm.ioctl.address(proc, vm)
    return vm.address
end

function kvm.ioctl.listen(proc, vm, ...)
    assert(proc.ring <= 1, "permission denied")
    local n = select("#", ...)
    for i=1, n do
        local v = select(i, ...)
        local s = tostring(v)
        kvm.listen(vm, s)
    end
    return true
end

function kvm.ioctl.forget(proc, vm, ...)
    assert(proc.ring <= 1, "permission denied")
    local n = select("#", ...)
    for i=1, n do
        local v = select(i, ...)
        local s = tostring(v)
        kvm.forget(vm, s)
    end
    return true
end

function kvm.ioctl.resume(proc, vm)
    if vm.mode == "halted" then
        return false, "halted"
    end
    if vm.mode == "restart" then
        -- Omega cheese
        kvm.init(vm)
        vm.mode = "running"
    end
    return KOCOS.resume(vm.instance)
end

function kvm.ioctl.traceback(proc, vm, err)
    return debug.traceback(vm.instance, err)
end

function kvm.ioctl.env(proc, vm)
    return vm.namespace
end

function kvm.ioctl.mode(proc, vm)
    return vm.mode
end

KOCOS.kvm = kvm
