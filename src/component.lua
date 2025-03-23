setmetatable(component, {
    __index = function(_, key)
        local primary = component.list(key)()
        if not primary then return nil end
        -- TODO: cache primaries
        return component.proxy(primary)
    end,
})

KOCOS.log("Component subsystem loaded")
