local gl = require("gl")
local backend = arg[1] or "gpu"
---@module "gl_terminal"
local device = require("gl." .. backend)

device.init()
local buf = gl.newScreenBuffer(device)

local w, h = buf.w, buf.h

local sunColor = gl.color(255, 255, 0)

local planets = {}

local function addPlanet(distance, speed, size, color)
    table.insert(planets, {distance = distance, speed = speed, size = size, angle = math.random() * math.pi * 2, color = color})
end

addPlanet(16, 1, 1, 0xA0A0A0FF)
addPlanet(25, 0.15, 4, 0xB38012FF)
addPlanet(35, 0.1, 4, 0x1D55B5FF)
addPlanet(48, 0.05, 3, 0xE35040FF)

while true do
    gl.clear(buf)

    local cx = math.floor(w/2)
    local cy = math.floor(h/2)

    gl.fillCircle(buf, cx, cy, 8, sunColor)

    for _, planet in ipairs(planets) do
        planet.angle = planet.angle + planet.speed
        local px = math.floor(cx + math.cos(planet.angle) * planet.distance)
        local py = math.floor(cy + math.sin(planet.angle) * planet.distance)
        gl.fillCircle(buf, px, py, planet.size, planet.color)
    end

    gl.flush(buf, device)

    coroutine.yield()
end
