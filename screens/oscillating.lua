local config = require("config")
local session = require("modules.session")

local oscillating = {}

local RADIUS = 24
local MARGIN = RADIUS + 40

-- Movement state
local x, direction, speed

-- Oscillation tracking
local oscillationCount

-- Pre-session state machine: "confirm" -> "playing_cue_in" -> (oscillation phases)
-- Oscillation phase state machine: "normal" -> "slowing" -> "breathe_in" -> "breathe_out"
local phase
local phaseTimer

-- Animated radius (changes during breathing phases, constant otherwise)
local currentRadius

-- Saved on load for reference during slowing phase
local baseSpeed

-- Critically damped spring coefficients (computed once at normal->slowing transition)
local springA, springB, springW

-- Which side of center the dot starts from (1 = right, -1 = left), used to prevent overshoot
local springSign

-- Cue-in audio source
local cueInSource = nil

-- Fonts
local hintFont, confirmFont

local function loadCueInAudio()
    local dir = session.selectedTargetDir
    if not dir then return nil end
    local path = dir .. "/cue_in.mp3"
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    if not data or #data == 0 then return nil end
    -- Write to Love2D save directory so love.audio can load it
    love.filesystem.write("cue_in_playback.mp3", data)
    local ok, src = pcall(love.audio.newSource, "cue_in_playback.mp3", "static")
    return ok and src or nil
end

function oscillating.load()
    local W = love.graphics.getWidth()
    x = W / 2
    direction = 1
    oscillationCount = 0

    speed = (W - MARGIN * 2) * config.oscillation_frequency * 2
    baseSpeed = speed

    phaseTimer = 0
    currentRadius = RADIUS
    springA = 0
    springB = 0
    springW = 0
    springSign = 1
    cueInSource = nil

    hintFont    = love.graphics.newFont(14)
    confirmFont = love.graphics.newFont(22)

    -- Show the confirmation + cue-in on the very first cycle, or once when
    -- resuming a paused/crashed session (re-anchors to the target memory).
    -- Other cycles (returning from notice_that) go straight to oscillating.
    if session.currentCycle <= 1 or session.resuming then
        phase = "confirm"
        session.resuming = false
    else
        phase = "normal"
    end
end

function oscillating.update(dt)
    local W = love.graphics.getWidth()
    local center = W / 2

    -- Phase: Confirm — waiting for user to press Enter
    if phase == "confirm" then
        return  -- nothing to animate

    -- Phase: Playing cue-in audio — wait for it to finish, then begin oscillation
    elseif phase == "playing_cue_in" then
        if cueInSource and not cueInSource:isPlaying() then
            cueInSource = nil
            phase = "normal"
        end
        return

    -- Phase: Normal — full-speed linear bounce (unchanged from original behaviour)
    elseif phase == "normal" then
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

            -- Critically damped spring: x(t) = center + (A + B*t) * e^(-w*t)
            -- A = initial offset from center
            -- B = initial velocity + w*A (ensures smooth velocity continuity)
            -- w = spring natural frequency (config.slowdown_stiffness)
            springW = config.slowdown_stiffness
            springA = x - center
            local v0 = direction * speed
            springB = v0 + springW * springA

            -- Remember which side of center we started on to prevent overshoot
            if x >= center then springSign = 1 else springSign = -1 end
        end

    -- Phase: Slowing — critically damped spring, clamped so the dot never overshoots center
    elseif phase == "slowing" then
        phaseTimer = phaseTimer + dt

        -- Critically damped spring position
        local decay = math.exp(-springW * phaseTimer)
        local offset = (springA + springB * phaseTimer) * decay

        -- Clamp: if the offset would cross center, pin it to center
        -- springSign is positive if we started right of center, negative if left
        if springSign * offset < 0 then
            offset = 0
        end

        x = center + offset

        -- Transition to breathing once at center
        if offset == 0 then
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

    if phase == "confirm" then
        -- Confirmation screen: prompt before cue-in audio plays
        love.graphics.setFont(confirmFont)
        love.graphics.setColor(0.85, 0.90, 1.0)

        local targetName = (session.selectedTargetName or "your target"):gsub("_", " ")
        local line1 = "Target: " .. targetName
        local line2 = "Are you ready to begin?"
        if session.currentCycle > 1 then
            line2 = string.format("Resuming at cycle %d of %d — ready to continue?",
                session.currentCycle, session.totalCycles)
        end
        love.graphics.print(line1, (W - confirmFont:getWidth(line1)) / 2, cy - 60)
        love.graphics.print(line2, (W - confirmFont:getWidth(line2)) / 2, cy - 10)

        love.graphics.setFont(hintFont)
        love.graphics.setColor(0.5, 0.6, 0.8)
        local hint = "Enter — begin   Escape — back to target selection"
        love.graphics.print(hint, (W - hintFont:getWidth(hint)) / 2, cy + 40)

    elseif phase == "playing_cue_in" then
        -- Show a quiet "listening" indicator while the cue-in plays
        love.graphics.setFont(confirmFont)
        love.graphics.setColor(0.6, 0.75, 0.95, 0.8)
        local msg = "Listen..."
        love.graphics.print(msg, (W - confirmFont:getWidth(msg)) / 2, cy - 16)

    else
        -- Oscillating dot (uses animated radius during breathing phases)
        love.graphics.setColor(0.72, 0.11, 0.20)
        love.graphics.circle("fill", x, cy, currentRadius)
    end

    -- Escape hint (always visible)
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.print("Escape — return to menu", 20, H - 36)
end

function oscillating.keypressed(k)
    if k == "escape" then
        if cueInSource then cueInSource:stop() end
        session.reset()
        switchScreen("menu")

    elseif k == "return" or k == "kpenter" then
        if phase == "confirm" then
            -- Try to load and play cue-in audio
            cueInSource = loadCueInAudio()
            if cueInSource then
                cueInSource:play()
                phase = "playing_cue_in"
            else
                -- No audio found — start oscillation directly
                phase = "normal"
            end
        end
    end
end

return oscillating
