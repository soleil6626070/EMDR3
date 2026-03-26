local config = require("config")
local session = require("modules.session")

local oscillating = {}

local RADIUS = 24
local MARGIN = RADIUS + 40

-- Movement state
local x, direction, speed

-- Oscillation tracking
local oscillationCount

-- Phase state machine: "normal" -> "slowing" -> "centering" -> "breathe_in" -> "breathe_out"
local phase
local phaseTimer

-- Animated radius (changes during breathing phases, constant otherwise)
local currentRadius

-- Saved on load for reference during slowing phase
local baseSpeed

-- Phase offset for damped sine continuity at normal->slowing transition
local phi0

-- Font for escape hint
local hintFont

function oscillating.load()
    local W = love.graphics.getWidth()
    x = W / 2
    direction = 1
    oscillationCount = 0

    -- Speed in pixels per second: full width travel in (1/freq) seconds
    speed = (W - MARGIN * 2) * config.oscillation_frequency * 2
    baseSpeed = speed

    -- Initialise phase state machine
    phase = "normal"
    phaseTimer = 0
    currentRadius = RADIUS
    phi0 = 0

    hintFont = love.graphics.newFont(14)
end

function oscillating.update(dt)
    local W = love.graphics.getWidth()
    local center = W / 2

    -- Phase: Normal — full-speed linear bounce (unchanged from original behaviour)
    if phase == "normal" then
        x = x + direction * speed * dt

        -- Bounce off right wall
        if x >= W - MARGIN then
            x = W - MARGIN
            direction = -1
        -- Bounce off left wall — counts as one full L->R->L oscillation
        elseif x <= MARGIN then
            x = MARGIN
            direction = 1
            oscillationCount = oscillationCount + 1
        end

        -- Transition to slowing phase when enough normal oscillations have completed
        local normalOscillations = config.oscillations - config.slowdown_oscillations
        if normalOscillations < 0 then normalOscillations = 0 end

        if oscillationCount >= normalOscillations then
            phase = "slowing"
            phaseTimer = 0

            -- Compute phi0 so damped sine matches current position and direction.
            -- sin(phi0) = normalised offset from center, quadrant chosen by direction.
            local A0 = (W - MARGIN * 2) / 2
            local offset = math.max(-1, math.min(1, (x - center) / A0))
            phi0 = math.asin(offset)
            if direction < 0 then
                phi0 = math.pi - phi0
            end
        end

    -- Phase: Slowing — damped sine wave, like a pendulum losing energy
    elseif phase == "slowing" then
        phaseTimer = phaseTimer + dt

        -- Damped sine parameters
        local A0    = (W - MARGIN * 2) / 2
        local omega = 2 * math.pi * config.oscillation_frequency
        local T     = config.slowdown_oscillations / config.oscillation_frequency
        local decay = config.slowdown_damping / T

        -- Exponentially decaying amplitude
        local amp = A0 * math.exp(-decay * phaseTimer)

        -- Parametric position: oscillates with shrinking amplitude
        x = center + amp * math.sin(omega * phaseTimer + phi0)

        -- Transition to centering when amplitude is negligible
        if amp < 1.5 then
            phase = "centering"
            phaseTimer = 0
        end

    -- Phase: Centering — exponential ease to exact screen center
    elseif phase == "centering" then
        x = x + (center - x) * math.min(1, 5 * dt)

        -- Snap to center once close enough
        if math.abs(x - center) < 0.5 then
            x = center
            phase = "breathe_in"
            phaseTimer = 0
        end

    -- Phase: Breathe In — circle grows from RADIUS to max (inhale cue)
    elseif phase == "breathe_in" then
        phaseTimer = phaseTimer + dt
        local t = math.min(phaseTimer / config.breathe_in_duration, 1.0)

        -- Sine easing: zero velocity at both endpoints for natural breath feel
        local eased = 0.5 - 0.5 * math.cos(t * math.pi)
        currentRadius = RADIUS + (config.breathe_max_radius - RADIUS) * eased

        if t >= 1.0 then
            phase = "breathe_out"
            phaseTimer = 0
        end

    -- Phase: Breathe Out — circle shrinks from max back to RADIUS (exhale cue)
    elseif phase == "breathe_out" then
        phaseTimer = phaseTimer + dt
        local t = math.min(phaseTimer / config.breathe_out_duration, 1.0)

        -- Same sine easing for symmetrical breathing feel
        local eased = 0.5 - 0.5 * math.cos(t * math.pi)
        currentRadius = config.breathe_max_radius
                      - (config.breathe_max_radius - RADIUS) * eased

        if t >= 1.0 then
            switchScreen("noticed")
        end
    end
end

function oscillating.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()
    local cy = H / 2

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Oscillating dot (uses animated radius during breathing phases)
    love.graphics.setColor(0.72, 0.11, 0.20)
    love.graphics.circle("fill", x, cy, currentRadius)

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
