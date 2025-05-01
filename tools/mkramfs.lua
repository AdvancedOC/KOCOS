-- We making RamFS now

local io = io

if not io.list then
    -- use lfs for stuff
    local lfs = require("lfs")

    function io.list(path)
        local files = {}
        for file in lfs.dir(path == "" and lfs.currentdir() or path) do
            if file ~= "." and file ~= ".." then
                table.insert(files, file)
            end
        end
        return files
    end

    function io.ftype(path)
        return lfs.attributes(path, "mode") or "missing"
    end
end

local ramfs = assert(io.open(".ramfs", "wb"))

local function writeBigEndian(n, size)
    local bytes = ""
    while n > 0 do
        bytes = bytes .. string.char(n % 256)
        n = math.floor(n / 256)
    end
    while #bytes < size do
        bytes = bytes .. "\0"
    end
    bytes = bytes:reverse()
    ramfs:write(bytes)
end

local function namePad(name)
    while #name < 64 do name = name .. "\0" end
    if #name > 64 then error("name too big") end
    return name
end

local function writeEntry(name, prefix)
    if name:sub(-1, -1) == "/" then name = name:sub(1, -2) end

    local path = prefix .. name
    print("Writing " .. path)

    if io.ftype(path) == "file" then
        local f = assert(io.open(path, "rb"))
        local c = f:read("a")
        f:close()
        ramfs:write(namePad(name))
        writeBigEndian(#c, 4)
        ramfs:write(c)
    else
        local entries = io.list(path)
        ramfs:write(namePad(name .. "/"))
        writeBigEndian(#entries, 2)
        for _, entry in ipairs(entries) do
            writeEntry(entry, path .. "/")
        end
    end
end

ramfs:write("KTAR\0")

for _, entry in ipairs(io.list("")) do
    if entry:sub(1, 1) ~= "." then
        writeEntry(entry, "")
    end
end

ramfs:close()
