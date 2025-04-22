---@class process
---@field pid integer
---@field stdout buffer
---@field stdin buffer
---@field stderr buffer
local process = {}
process.__index = process

return process
