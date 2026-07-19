local transcription  = require("modules.transcription")
local config         = require("config")
local session        = require("modules.session")
local identification = require("modules.identification")
local cue_in         = require("modules.cue_in")

local menu = {}

local options = {}   -- { { label, action }, ... } — rebuilt on load
local selected = 1

--- Build the option list, prepending a Resume entry when a paused/crashed
--- session's marker exists and its target folder is still present.
local function buildOptions()
    options = {}

    local ongoing = session.getOngoing()
    if ongoing then
        local probe = io.open(ongoing.targetDir .. "/script.txt", "r")
        if probe then
            probe:close()
            local name = ongoing.targetName ~= "" and ongoing.targetName or "unknown target"
            table.insert(options, {
                label = string.format("Resume Session — %s (cycle %d/%d)",
                    name:gsub("_", " "),
                    math.min(ongoing.lastCompleted + 1, ongoing.totalCycles),
                    ongoing.totalCycles),
                action = function()
                    session.resume(ongoing)
                    if session.currentCycle > session.totalCycles then
                        -- Crashed after the final cycle: only the post-rating remains
                        switchScreen("post_rating")
                    else
                        switchScreen("oscillating")
                    end
                end,
            })
        end
    end

    -- Resume a paused/crashed identification (marker validated against its
    -- assessment record; the first incomplete step is derived from the record)
    local identOngoing = identification.getOngoing()
    if identOngoing then
        table.insert(options, {
            label = string.format("Resume Identification — %s (%s)",
                identOngoing.targetName:gsub("_", " "), identOngoing.nextStepLabel),
            action = function() identification.resume(identOngoing) end,
        })
    end

    table.insert(options, {
        label = "Target Identification",
        action = function() identification.begin() end,
    })
    table.insert(options, {
        label = "Start Session",
        action = function() switchScreen("target_select") end,
    })
    -- DEV: jump straight into the assessment stages with a stubbed image,
    -- skipping prelude + agent call. Removed once the full flow is wired.
    table.insert(options, {
        label = "DEV: Stage Test",
        action = function()
            identification.reset()
            identification.started = os.date("%Y-%m-%d %H:%M:%S")
            identification.beginTarget({
                slug = "dev_stage_test",
                image = "you are standing alone in the rain outside the school gates",
                confirmed = true,
            })
            identification.stepIndex = 1   -- image step; advance lands on nc
            identification.advance()
        end,
    })

    table.insert(options, {
        label = "Quit",
        action = function() love.event.quit() end,
    })
end

local bgShader
local time = 0
local spinTime = 0
local fontTitle, fontSub, fontMenu, fontHint

-- Calm blue/teal palette for the background
local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

function menu.load()
    buildOptions()
    selected = 1
    time = 0
    spinTime = 0
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
        local optW = fontMenu:getWidth(option.label)
        local x = (W - optW) / 2
        local y = startY + (i - 1) * 56

        if i == selected then
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("> " .. option.label .. " <", x - fontMenu:getWidth("> "), y)
        else
            love.graphics.setColor(0.65, 0.75, 0.90)
            love.graphics.print(option.label, x, y)
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

    -- Cue-in generation indicator (runs in the background after review confirm)
    local cueStatus = cue_in.getStatus()
    if cueStatus == "generating" then
        love.graphics.setFont(fontHint)
        local msg = "Generating cue-in audio..."
        love.graphics.setColor(0.9, 0.8, 0.3)
        love.graphics.print(msg, (W - fontHint:getWidth(msg)) / 2, H - 88)
    elseif cueStatus == "error" then
        love.graphics.setFont(fontHint)
        local msg = "Cue-in generation failed: " .. tostring(cue_in.getError()):sub(1, 80)
            .. "   (T on target select retries)"
        love.graphics.setColor(0.9, 0.5, 0.4)
        love.graphics.print(msg, (W - fontHint:getWidth(msg)) / 2, H - 88)
    end

    -- Controls hint
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.55, 0.65, 0.80)
    local hintText = "↑↓ Navigate   Enter Select"
    local hintW = fontHint:getWidth(hintText)
    love.graphics.print(hintText, (W - hintW) / 2, H - 40)

end

function menu.keypressed(k)
    if k == "up" then
        selected = selected - 1
        if selected < 1 then selected = #options end
    elseif k == "down" then
        selected = selected + 1
        if selected > #options then selected = 1 end
    elseif k == "return" or k == "kpenter" then
        options[selected].action()
    elseif k == "escape" or k == "q" then
        love.event.quit()
    end
end

return menu
