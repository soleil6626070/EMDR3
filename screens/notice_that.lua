local session = require("modules.session")

local notice_that = {}

local source
local font, hintFont
local phase       -- "playing", "fading", "done"
local fadeAlpha
local FADE_DURATION = 1.5

function notice_that.load()
    phase = "playing"
    fadeAlpha = 1.0

    font = love.graphics.newFont(36)
    hintFont = love.graphics.newFont(14)

    -- Pick random audio from notice_that folder
    local variants = {}
    local items = love.filesystem.getDirectoryItems("resources/audio/notice_that")
    for _, name in ipairs(items) do
        table.insert(variants, "resources/audio/notice_that/" .. name)
    end

    if #variants > 0 then
        local pick = variants[love.math.random(#variants)]
        source = love.audio.newSource(pick, "static")
        source:play()
    else
        -- No audio — skip straight to fading
        source = nil
        phase = "fading"
    end
end

function notice_that.update(dt)
    if phase == "playing" then
        if source and not source:isPlaying() then
            phase = "fading"
        end
    elseif phase == "fading" then
        fadeAlpha = fadeAlpha - dt / FADE_DURATION
        if fadeAlpha <= 0 then
            fadeAlpha = 0
            phase = "done"
        end
    elseif phase == "done" then
        session.nextCycle()
        switchScreen("oscillating")
    end
end

function notice_that.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Centered "Notice that" text with fade
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, fadeAlpha)
    local text = "Notice that"
    local textW = font:getWidth(text)
    love.graphics.print(text, (W - textW) / 2, H / 2 - font:getHeight() / 2)

    -- Hint
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4, fadeAlpha)
    love.graphics.print("Escape — return to menu", 20, H - 36)
end

function notice_that.keypressed(k)
    if k == "escape" then
        if source then source:stop() end
        session.reset()
        switchScreen("menu")
    end
end

return notice_that
