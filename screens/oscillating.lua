local oscillating = {}

local RADIUS = 24
local SPEED_HZ = 0.5   -- full sweeps per second (one left→right = 1 sweep)
local MARGIN = RADIUS + 40

local x, direction, speed

function oscillating.load()
    local W = love.graphics.getWidth()
    x = W / 2
    direction = 1
    -- speed in pixels per second: full width travel in (1/SPEED_HZ) seconds
    speed = (W - MARGIN * 2) * SPEED_HZ * 2
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
    end
end

function oscillating.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local cy = H / 2

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Oscillating dot
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("fill", x, cy, RADIUS)

    -- Escape hint
    local hintFont = love.graphics.newFont(14)
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.print("Escape — return to menu", 20, H - 36)
end

function oscillating.keypressed(k)
    if k == "escape" then
        switchScreen("menu")
    end
end

return oscillating
