local auth = {}

---@param user integer
---@param group integer
---@return boolean
function auth.isUserInGroup(user, group)
    return false
end

---@return integer[]
function auth.listGroups()
    return {}
end

---@param group integer?
---@return integer[]
function auth.listUsers(group)
    if group then return {} end
    -- Only root exists
    return {0}
end

---@param user integer
---@return {name: string, groups: integer[], hasPassword: boolean}?
function auth.userInfo(user)
    if user ~= 0 then return end
    return {
        name = "root",
        groups = {},
        hasPassword = false,
    }
end

---@param group integer
---@return {name: string, desc: string, users: integer[]}?
function auth.groupInfo(group)
    return nil -- no groups
end

---@param user integer
---@param ring integer
---@param password string 
---@return boolean
function auth.isAllowed(user, ring, password)
    return user == 0
end

---@param name string
---@return integer?
function auth.userByName(name)
    if name == "root" then return 0 end
end

---@param name string
---@return integer?
function auth.groupByName(name)
    return nil -- no groups
end

-- Overwrite with better auth plz
KOCOS.auth = auth

local perms = {}

perms.BIT_WRITABLE = 1
perms.BIT_READABLE = 2
perms.ID_BITS = 6
perms.ID_ALL = 2^perms.ID_BITS - 1

function perms.encode(user, userRW, group, groupRW)
    local userPerms = user * 4 + userRW
    local groupPerms = group * 4 + groupRW

    return groupPerms * 256 + userPerms
end

function perms.decode(num)
    local userPerms = num % 256
    local groupPerms = math.floor(num / 256)

    local user = math.floor(userPerms / 4)
    local userRW = userPerms % 4

    local group = math.floor(groupPerms / 4)
    local groupRW = groupPerms % 4

    return user, userRW, group, groupRW
end

function perms.canWrite(puser, permissions)
    -- Root can do anything
    if puser == 0 then return true end
    local user, userRW, group, groupRW = perms.decode(permissions)
    if puser == user or user == perms.ID_ALL then
        return bit32.btest(userRW, perms.BIT_WRITABLE)
    end
    if KOCOS.auth.isUserInGroup(user, group) or group == perms.ID_ALL then
        return bit32.btest(groupRW, perms.BIT_WRITABLE)
    end
    return false
end

function perms.canRead(puser, permissions)
    -- Root can do anything
    if puser == 0 then return true end
    local user, userRW, group, groupRW = perms.decode(permissions)
    if puser == user or user == perms.ID_ALL then
        return bit32.btest(userRW, perms.BIT_READABLE)
    end
    if KOCOS.auth.isUserInGroup(user, group) or group == perms.ID_ALL then
        return bit32.btest(groupRW, perms.BIT_READABLE)
    end
    return false
end

KOCOS.perms = perms

KOCOS.log("Auth and perms subsystems loaded")
