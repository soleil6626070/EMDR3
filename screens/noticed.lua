local noticed = {}

local source
local font, hintFont
local finished = false
local delayTimer = 0
local DELAY_AFTER_AUDIO = 0.5

function noticed.load()
    finished = false
    delayTimer = 0

    -- Scan for what_noticed_*.mp3 variants
    local variants = {}
    local items = love.filesystem.getDirectoryItems("resources/audio")
    for _, name in ipairs(items) do
        if name:match("^what_noticed_%d+%.mp3$") then
            table.insert(variants, "resources/audio/" .. name)
        end
    end

    -- Pick a random variant and play it
    if #variants > 0 then
        local pick = variants[love.math.random(#variants)]
        source = love.audio.newSource(pick, "static")
        source:play()
    else
        -- No audio files found — skip straight to finished state
        source = nil
        finished = true
    end

    font = love.graphics.newFont(36)
    hintFont = love.graphics.newFont(14)
end

function noticed.update(dt)
    if finished then
        delayTimer = delayTimer + dt
        if delayTimer >= DELAY_AFTER_AUDIO then
            switchScreen("menu")
        end
        return
    end

    if source and not source:isPlaying() then
        finished = true
    end
end

function noticed.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Centered prompt text
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1)
    local text = "What did you notice?"
    local textW = font:getWidth(text)
    love.graphics.print(text, (W - textW) / 2, H / 2 - font:getHeight() / 2)

    -- Hint
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4)
    love.graphics.print("Space/Enter — continue   Escape — menu", 20, H - 36)
end

function noticed.keypressed(k)
    if k == "space" or k == "return" or k == "kpenter" then
        if source then source:stop() end
        switchScreen("menu")
    elseif k == "escape" then
        if source then source:stop() end
        switchScreen("menu")
    end
end

return noticed
