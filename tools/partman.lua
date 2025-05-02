print("partman - Partition Manager")

local drives = {}
for addr in _K.vdrive.list() do
    table.insert(drives, addr)
end

for i, drive in ipairs(drives) do
    local label = component.invoke(drive, "getLabel")
    label = label or drive:sub(1, 8)

    printf("%d. %s", i, label)
end

io.write("Input index: ")
local input = io.read("l")

local selected = drives[tonumber(input)]
assert(selected, "bad input")

local drive = _K.vdrive.proxy(selected)
assert(drive, "drive no longer available")

local capacity = drive.getCapacity()
local sectorSize = drive.getSectorSize()

printf("Drive Size: %s", string.memformat(capacity))
printf("Drive Sector Size: %s", string.memformat(sectorSize))

local units = {
    B = 1,
    K = 1024,
    M = 1024*1024,
    G = 1024*1024*1024,
    T = 1024*1024*1024*1024,
    ["%"] = capacity / 100,
}

local function parseByteCount(amount)
    if tonumber(amount) then return tonumber(amount) end
    local unit = amount:sub(-1, -1)
    local n = tonumber(amount:sub(1, -2))
    if not n then return nil end
    return n * (units[unit] or 1)
end

---@alias partman.partition {name: string, start: integer, size: integer, kind: "user" | "root" | "boot" | "reserved"}

---@type {[string]: fun(partitions: partman.partition[])}
local formatters = {}

function formatters.mtpt(parts)
    local maxSectorCount = math.floor(sectorSize / 32) - 1 -- 1 is taken for header

    assert(#parts <= maxSectorCount, "too many partitions")

    local eformat = "c20c4>I4>I4"
    local rootSector = string.pack(eformat, "", "mtpt", 0, 0) -- header

    for i=1,#parts do
        local part = parts[i]
        local t = "user"
        if part.kind == "boot" then
            t = "boot"
        elseif part.kind == "reserved" then
            t = "back"
        elseif part.kind == "root" then
            t = "kcos"
        end
        local s = 1 + part.start / sectorSize
        assert(math.floor(s) == s, "partition " .. i .. " is not sector aligned")
        local l = part.size / sectorSize
        assert(math.floor(l) == l, "partition " .. i .. " is not sector aligned")
        rootSector = rootSector .. string.pack(eformat, part.name, t, s, l)
    end

    rootSector = string.rightpad(rootSector, sectorSize)

    local lastSector = math.floor(capacity / sectorSize)
    printf("Writing to sector %d", lastSector)
    drive.writeSector(lastSector, rootSector)
end

function formatters.osdi(parts)
    local maxSectorCount = math.floor(sectorSize / 32) - 1 -- 1 is taken for header
    assert(#parts <= maxSectorCount, "too many partitions")

    local magic = "OSDI\xAA\xAA\x55\x55"
    local pack_format = "<I4I4c8I3c13"
    local partTable = string.pack(pack_format, 1, 0, magic, 0, drive.getLabel() or "")

    for i, part in ipairs(parts) do
        local t = ""
        local flags = 0
        if part.kind == "boot" then
            flags = flags + 512
        elseif part.kind == "reserved" then
            t = "" -- data loss!!
        elseif part.kind == "root" then
            t = "kocos"
        end
        local name = string.rightpad(part.name, 13)
        t = string.rightpad(t, 8)

        local start = 1 + part.start / sectorSize
        assert(math.floor(start) == start, "partition " .. i .. " is not sector aligned")
        local size = part.size / sectorSize
        assert(math.floor(size) == size, "partition " .. i .. " is not sector aligned")

        partTable = partTable .. string.pack(pack_format, start, size, t, flags, name)
    end

    partTable = string.rightpad(partTable, sectorSize)

    drive.writeSector(1, partTable)
end

while true do
    print("Create Partitions")
    ---@type partman.partition[]
    local partitions = {}
    while true do
        io.write("Name (empty or Ctrl-D to stop): ")
        local name = io.read("l")
        if not name then break end
        if name == "" then break end
        io.write("Start: ")
        local startByte = parseByteCount(io.read("l"))
        assert(startByte, "bad byte count")
        io.write("Size: ")
        local byteSize = parseByteCount(io.read("l"))
        assert(byteSize, "bad byte size")
        io.write("Type (user/root/boot/reserved): ")
        local kind = io.read("l")
        assert(kind == "user" or kind == "root" or kind == "boot" or kind == "reserved", "bad partition type")

        table.insert(partitions, {
            name = name,
            start = startByte,
            size = byteSize,
            kind = kind,
        })
    end
    assert(#partitions > 0, "there must be at least 1 partition")

    local options = {}
    for k in pairs(formatters) do
        table.insert(options, k)
    end
    table.sort(options)

    io.write("Partition format (" .. table.concat(options, "/") ..  "): ")
    local partFormat = io.read("l")
    local formatter = assert(formatters[partFormat], "unknown format")

    print("Last chance to confirm partition layout:")
    for i, part in ipairs(partitions) do
        printf(
            "%d. %s | %s | %s - %s | %s", i, part.name, string.memformat(part.size),
            string.memformat(part.start), string.memformat(part.start + part.size),
            part.kind
        )
    end

    io.write("Confirm [y/N]: ")
    input = io.read("l")
    if input:lower():sub(1, 1) == "y" then
        formatter(partitions)
        break
    else
        print("Discarding old partition list")
    end
end

print("It is advised to reformat the new partitions to ensure there is some usable data on them")
