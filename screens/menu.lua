local transcription = require("modules.transcription")
local session       = require("modules.session")
local config        = require("config")

local menu = {}

local options = { "Target Identification", "Start Session", "Quit" }
local selected = 1

local bgShader
local time = 0
local spinTime = 0
local fontTitle, fontSub, fontMenu, fontHint

-- Resume prompt state
local showResumePrompt = false
local resumeTimestamp = nil
local resumeCycle = nil

-- Calm blue/teal palette for the background
local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

function menu.load()
    selected = 1
    time = 0
    spinTime = 0
    showResumePrompt = false
    resumeTimestamp = nil
    resumeCycle = nil
    bgShader = love.graphics.newShader("resources/shaders/background.fs")
    fontTitle = love.graphics.newFont(64)
    fontSub   = love.graphics.newFont(18)
    fontMenu  = love.graphics.newFont(28)
    fontHint  = love.graphics.newFont(14)
end

-- Dictates menu background movement speed
function menu.update(dt)
    time = time + dt
    spinTime = spinTime + dt * 0.1
end

function menu.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    -- Draw animated background shader
    bgShader:send("time", time)
    bgShader:send("spin_time", spinTime)
    bgShader:send("colour_1", colour1)
    bgShader:send("colour_2", colour2)
    bgShader:send("colour_3", colour3)
    bgShader:send("contrast", 1.0)
    bgShader:send("spin_amount", 0.0)
    love.graphics.setShader(bgShader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setShader()

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(fontTitle)
    local titleText = "EMDR3"
    local titleW = fontTitle:getWidth(titleText)
    love.graphics.print(titleText, (W - titleW) / 2, H * 0.25)

    -- Subtitle
    love.graphics.setFont(fontSub)
    love.graphics.setColor(0.85, 0.90, 1.0)
    local subText = "Eye Movement Desensitisation & Reprocessing"
    local subW = fontSub:getWidth(subText)
    love.graphics.print(subText, (W - subW) / 2, H * 0.25 + 74)

    -- Menu options
    love.graphics.setFont(fontMenu)
    local startY = H * 0.55

    for i, option in ipairs(options) do
        local optW = fontMenu:getWidth(option)
        local x = (W - optW) / 2
        local y = startY + (i - 1) * 56

        if i == selected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("> " .. option .. " <", x - fontMenu:getWidth("> "), y)
        else
            love.graphics.setColor(0.65, 0.75, 0.90)
            love.graphics.print(option, x, y)
        end
    end

    -- Transcription progress indicator
    if not transcription.isIdle() then
        love.graphics.setFont(fontHint)
        local done = transcription.getCompletedCount()
        local total = done + transcription.getPendingCount()
        local statusText = string.format("Transcribing responses... (%d/%d)", done, total)
        local statusW = fontHint:getWidth(statusText)
        love.graphics.setColor(0.9, 0.8, 0.3)
        love.graphics.print(statusText, (W - statusW) / 2, H - 64)
    end

    -- Controls hint
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.55, 0.65, 0.80)
    local hintText = "↑↓ Navigate   Enter Select"
    local hintW = fontHint:getWidth(hintText)
    love.graphics.print(hintText, (W - hintW) / 2, H - 40)

    -- Resume prompt overlay
    if showResumePrompt then
        -- Semi-transparent background
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.rectangle("fill", 0, 0, W, H)

        -- Centered prompt box
        local boxW, boxH = 500, 160
        local boxX = (W - boxW) / 2
        local boxY = (H - boxH) / 2

        love.graphics.setColor(0.12, 0.14, 0.18)
        love.graphics.rectangle("fill", boxX, boxY, boxW, boxH, 12, 12)
        love.graphics.setColor(0.3, 0.5, 0.7)
        love.graphics.rectangle("line", boxX, boxY, boxW, boxH, 12, 12)

        love.graphics.setFont(fontMenu)
        love.graphics.setColor(1, 1, 1)
        local promptText = "Resume previous session?"
        local promptW = fontMenu:getWidth(promptText)
        love.graphics.print(promptText, (W - promptW) / 2, boxY + 30)

        love.graphics.setFont(fontSub)
        love.graphics.setColor(0.7, 0.8, 0.9)
        local detailText = string.format("Session %s — cycle %d completed",
            resumeTimestamp, resumeCycle)
        local detailW = fontSub:getWidth(detailText)
        love.graphics.print(detailText, (W - detailW) / 2, boxY + 75)

        love.graphics.setColor(0.55, 0.65, 0.80)
        local keyText = "Y — Resume     N — New session"
        local keyW = fontSub:getWidth(keyText)
        love.graphics.print(keyText, (W - keyW) / 2, boxY + 110)
    end
end

function menu.keypressed(k)
    -- Handle resume prompt keys first
    if showResumePrompt then
        if k == "y" then
            showResumePrompt = false
            session.resume(config.cycles, resumeTimestamp, resumeCycle)
            switchScreen("oscillating")
        elseif k == "n" then
            showResumePrompt = false
            session.clearOngoing()
            session.start(config.cycles)
            switchScreen("oscillating")
        elseif k == "escape" then
            showResumePrompt = false
        end
        return
    end

    if k == "up" then
        selected = selected - 1
        if selected < 1 then selected = #options end
    elseif k == "down" then
        selected = selected + 1
        if selected > #options then selected = 1 end
    elseif k == "return" or k == "kpenter" then
        if selected == 1 then
            switchScreen("target_identification")
        elseif selected == 2 then
            -- Check for an ongoing session before starting
            local ts, cycle = session.getOngoing()
            if ts then
                resumeTimestamp = ts
                resumeCycle = cycle
                showResumePrompt = true
            else
                session.start(config.cycles)
                switchScreen("oscillating")
            end
        elseif selected == 3 then
            love.event.quit()
        end
    elseif k == "escape" or k == "q" then
        love.event.quit()
    end
end

return menu
