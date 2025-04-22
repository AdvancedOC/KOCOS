local radio = {}

radio.ADDR_BROADCAST = "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"
radio.ADDR_LOOP = "00000000-0000-0000-0000-000000000000"

--[[

Radio Signal (fancier modem_message)

"sender" port "data" distance time

]]

function radio.primaryModem()
    if component.type(radio._prim or "") ~= "modem" then
        radio._prim = component.modem.address
    end
    return radio._prim
end

-- modem_message(receiverAddress: string, senderAddress: string, port: number, distance: number
function radio.handler(event, receiver, sender, port, distance, data)
    if event ~= "modem_message" then return end
end

radio.listener = KOCOS.event.listen(radio.handler)

KOCOS.radio = radio
