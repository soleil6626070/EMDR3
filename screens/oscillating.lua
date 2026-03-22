local config = require("config")
local session = require("modules.session")

local oscillating = {}

local RADIUS = 24
local MARGIN = RADIUS + 40

local x, direction, speed
local oscillationCount
local hintFont

function oscillating.load()
    local W = love.graphics.getWidth()
    x = W / 2
    direction = 1
    oscillationCount = 0
    -- speed in pixels per second: full width travel in (1/freq) seconds
    speed = (W - MARGIN * 2) * config.oscillation_frequency * 2

    hintFont = love.graphics.newFont(14)
end

function oscillating.update(dt)
    local W = love.graphics.getWidth()
    x = x + direction * speed * dt

    if x >= W - MARGIN then
        x = W - MARGIN
        direction = -1
    elseif x <= MARGIN then
        x = MARGIN
        direction = 1
        -- One full L→R→L oscillation completes on left-wall bounce
        oscillationCount = oscillationCount + 1
    end

    if oscillationCount >= config.oscillations then
        switchScreen("noticed")
    end
end

function oscillating.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local cy = H / 2

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Oscillating dot
    love.graphics.setColor(0.72, 0.11, 0.20)
    love.graphics.circle("fill", x, cy, RADIUS)

    -- Escape hint
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.print("Escape — return to menu", 20, H - 36)
end

function oscillating.keypressed(k)
    if k == "escape" then
        session.reset()
        switchScreen("menu")
    end
end

return oscillating
