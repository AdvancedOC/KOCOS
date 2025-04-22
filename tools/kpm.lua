-- Minimum barely usable version of KOCOS Package Manager.
-- This is internet-only, and sucks.
-- It does not support un-installing

local sys = require("syscalls")
local lon = require("lon")
local internetAddr = assert(sys.cprimary("internet"))
printf("Using internet card %s...", internetAddr)
local internet = assert(sys.cproxy(internetAddr))

-- Just makes a GET lol
local function actuallyDownload(url)
    local req = internet.request(url)
    req.finishConnect()
    local data = ""
    while true do
        local chunk = req.read(math.huge)
        if not chunk then break end
        data = data .. chunk
    end
    req.close()
    return data
end

local function download(url)
    local ok, data = pcall(actuallyDownload, url)
    if ok then return data end
    return nil, data
end

local function ensureParent(path)
    local parent = io.parentOf(path)
    if io.exists(parent) then return end
    ensureParent(parent)
    assert(io.mkdir(parent, 2^16-1))
end

local function readFile(path)
    local f = assert(io.open(path, "r"))
    local data = f:read("a")
    f:close()
    return data
end

local action = arg[1]
local subargs = {table.unpack(arg, 2)}

if action ~= "install" then
    error("unsupported action: " .. action)
end

local conf = lon.decode(readFile("/etc/kpm.conf"))

local allPackages = {}
local order = {}

local function queryPackageInfo(package)
    if allPackages[package] then return end
    table.insert(order, package)
    printf("Searching for %s...", package)
    for _, repo in ipairs(conf.repos) do
        if repo.type == "internet" then
            local f, err = download(repo.repo .. "/" .. package .. ".kpm")
            _K.logAll(f, err)
            if f then
                local info = lon.decode(f)
                info.url = repo.repo
                allPackages[package] = info
                for _, dep in ipairs(info.dependencies) do
                    queryPackageInfo(dep)
                end
                return
            end
        end
    end
    error("Missing package: " .. package)
end

for i=1,#subargs do
    queryPackageInfo(subargs[i])
end

local function installPackage(info)
    --[[
    -- Basic package example
    {
        name = "name",
        author = "author",
        version = "major.minor.patch",
        files = {
            ["path"] = "local in repo path",
        },
        extraFiles = {
            "stuff to also consider part of package",
        },
        keepFiles = {
            "stuff to keep once uninstalling",
        },
        dependencies = {
            "stuff to also install",
        },
        postInstall = {
            "shell commands to run post install",
        },
    }
    ]]
    printf("Installing %s v%s...", info.name, info.version)
    for fullPath, remotePath in pairs(info.files) do
        printf("Downloading %s...", remotePath)
        local url = info.url .. "/" .. remotePath
        local data = assert(download(url))
        printf("Writing %s...", fullPath)
        ensureParent(fullPath)
        local f = assert(io.open(fullPath, "w"))
        f:write(data)
        f:close()
    end
    if #info.postInstall > 0 then
        print("Running post install scripts...")
        for _, cmd in ipairs(info.postInstall) do
            printf("+%s", cmd)
            assert(os.execute(cmd), "command failed")
        end
    end
end

-- Installation
for _, p in ipairs(order) do
    installPackage(allPackages[p])
end
