-- TODO: refactor to use kernel audio once thats made

local path = assert(arg[1], "no path given")
local file = assert(io.open(path, "rb"))

local function readLE(len)
    len = len or 1
    local buf = file:read(len)
    if not buf then return 0 end -- lol
    local n = 0
    buf = buf:reverse()
    for i=1,#buf do
        n = n + buf:byte(i, i)
    end
    return n
end

local function makeSigned(n, len)
    len = len or 1
    local signBit = 2^(len*8-1)
    if n < signBit then return n end
    -- if n is signBit, n is -signBit. If n is 2^len-1, n is -1
    return n - 2 * signBit
end

local function readString()
    local len = readLE(4)
    return file:read(len)
end

assert(readLE(2) == 0, "file is not using new NBS format")
printf("NBS version: %d\n", readLE(1))
local instrumentCount = readLE(1)
printf("NBS instrument count: %d\n", instrumentCount)

local tickCount = readLE(2)
printf("Tick Count: %d\n", tickCount)
local layerCount = readLE(2)
printf("Layer Count: %d\n", layerCount)
local name = readString()
local author = readString()
readString() -- original author
readString() -- description
printf("Playing: %s by %s", name, author)

local tps = readLE(2)

printf("TPS: %f", tps)
printf("Duration: %fs", tickCount/tps)

readLE(1) -- auto saving
readLE(1) -- auto saving duration
readLE(1) -- time signature
readLE(4) -- minutes spent
readLE(4) -- left-clicks
readLE(4) -- right-clicks
readLE(4) -- note blocks added
readLE(4) -- note blocks removed
readString() -- MIDI/Schematic file
readLE() -- loop on/off
readLE() -- max loop count
readLE(2) -- loop start ticks

local function mapKeyToNote(key)
    return key - 33 + 1
end

---@type {[integer]: {instrument: integer, note: integer, volume: number}[]}
local noteData = {}

local tick = 0

print("Reading noteblock data...")
while true do
    local jmpTick = makeSigned(readLE(2), 2)
    if jmpTick == 0 then break end
    tick = tick + jmpTick
    while true do
        local jmpLayer = makeSigned(readLE(2), 2)
        if jmpLayer == 0 then break end
        local instrument = readLE(1)
        local key = readLE(1)

        local vel = readLE(1)
        readLE(1) -- pan
        readLE(2) -- pitch

        noteData[tick] = noteData[tick] or {}
        if mapKeyToNote(key) then
            table.insert(noteData[tick], {
                instrument = instrument,
                note = mapKeyToNote(key),
                volume = vel / 100,
            })
        end
    end
end
print("Noteblock data read")

file:close()

local speaker = component.proxy(component.list("note")())
assert(speaker, "Missing speaker")

-- Don't care about layer controls, fuck off

for i=1,tickCount do
    local noteLayer = noteData[i]
    if noteLayer then
        for _, block in ipairs(noteLayer) do
            if speaker.type == "note_block" then
                speaker.trigger(math.clamp(block.note, 1, 25))
            elseif speaker.type == "iron_noteblock" then
                speaker.playNote(block.instrument, block.note-1, block.volume)
            end
        end
    end
    coroutine.yield(1/tps)
end
