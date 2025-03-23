local event

---@param maximum number
event = function(maximum)
    local buffer = {}
    local callbacks = {}
    ---@class KOCOS.EventSystem
    local system = {}

    function system.push(name, ...)
        table.insert(buffer, {name, ...})
        -- callback order is undefined
        for _, callback in pairs(callbacks) do
            local ok, err = pcall(callback, name, ...)
            if not ok and name ~= "event_err" then
                system.push("event_err", err, name)
            end
        end
        while #buffer > maximum do
            -- THIS MAY DISCARD SHIT SO CAREFULLLL
            table.remove(buffer, 1)
        end
    end


    function system.popWhere(f)
        for i=1,#buffer do
            if f(table.unpack(buffer[i])) then
                return table.unpack(table.remove(buffer, i))
            end
        end
    end

    function system.pop(...)
        local allowed = {...}
        if #allowed == 0 then
            -- we love heap allocs
            return table.unpack(table.remove(buffer, 1) or {})
        end

        return system.popWhere(function(kind)
            for i=1,#allowed do
                if kind == allowed[i] then return true end
            end
            return false
        end)
    end

    function system.queued(...)
        local allowed = {...}
        if #allowed == 0 then return #buffer > 1 end
        for i=1,#buffer do
            for j=1,#allowed do
                if buffer[i][1] == allowed[j] then return true end
            end
        end
        return false
    end

    function system.process(timeout)
        local s = {computer.pullSignal(timeout)}
        if #s > 0 then
            system.push(table.unpack(s))
        end
    end

    function system.listen(callback, id)
        id = tostring(callback)
        while callbacks[id] do id = "_" .. id end
        callbacks[id] = callback
        for i=1,#buffer do
            callback(table.unpack(buffer))
        end
        return id
    end

    function system.forget(id)
        callbacks[id] = nil
    end

    function system.clear()
        buffer = {}
    end

    system.create = event

    return system
end

KOCOS.event = event(KOCOS.maxEventBacklog)

KOCOS.log("Event subsystem loaded")
