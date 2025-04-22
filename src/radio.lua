local radio = {}

radio.ADDR_BROADCAST = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
radio.ADDR_LOOP = "00000000-0000-0000-0000-000000000000"

--[[

Radio Signal (fancier modem_message)

"radio_message" "sender" port "data" distance

]]

radio.RADIO_EVENT = "radio_message"
radio.RADIO_TUNNEL_PORT = -1

function radio.signal(sender, port, data, distance)
    KOCOS.event.push(radio.RADIO_EVENT, sender, port, data, distance, computer.uptime())
end

function radio.primaryModem()
    if component.type(radio._prim or "") ~= "modem" then
        radio._prim = (component.modem or {}).address
    end
    return radio._prim
end

-- modem_message(receiverAddress: string, senderAddress: string, port: number, distance: number
function radio.handler(event, receiver, sender, port, distance, data)
    if event ~= "modem_message" then return end
    if component.type(receiver) == "tunnel" then
        radio.signal(sender, radio.RADIO_TUNNEL_PORT, data, distance)
        return
    end
    if receiver ~= radio.primaryModem() then return end
    if type(data) ~= "string" then return end
    radio.signal(sender, port, data, distance)
end

function radio.send(addr, port, data)
    data = tostring(data)
    if addr == radio.ADDR_LOOP then
        radio.signal(radio.ADDR_LOOP, port, data, 0)
        return true
    end
    if component.type(addr) == "tunnel" then
        local t = component.proxy(addr)
        return t.send(addr, data)
    end
    local m = radio.primaryModem()
    if not m then return false, "offline" end
    local modem = component.proxy(m)
    if addr == radio.ADDR_BROADCAST then
        for tunnel in component.list("tunnel") do
            local t = component.proxy(tunnel)
            t.send(addr, data)
        end
        return modem.broadcast(port, data)
    end
    return modem.send(addr, port, data)
end

function radio.isOpen(p)
    local m = radio.primaryModem()
    if not m then return false end
    local modem = component.proxy(m)
    return modem.isOpen(p)
end

function radio.open(p)
    local m = radio.primaryModem()
    if not m then return false, "offline" end
    local modem = component.proxy(m)
    return modem.open(p)
end

function radio.close(p)
    local m = radio.primaryModem()
    if not m then return false, "offline" end
    local modem = component.proxy(m)
    return modem.close(p)
end

radio.listener = KOCOS.event.listen(radio.handler)

KOCOS.radio = radio
