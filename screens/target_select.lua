-- screens/target_select.lua
-- Lists all available target images (each folder under output_data/targets/
-- that has a cue_in.mp3). The user picks one to start a session, or presses
-- R to review/edit the script before starting.

local config  = require("config")
local session = require("modules.session")

local target_select = {}

local fontTitle, fontBody, fontHint
local targets = {}   -- array of { name = "slug", dir = "/abs/path/slug", hasAudio = bool }
local selected = 1
local cue_in_status_msg = nil  -- brief feedback shown when generation is in progress

local function scanTargets()
    targets = {}
    local cue_in = require("modules.cue_in")
    local baseDir = love.filesystem.getSource() .. "/" .. (config.TARGETS_DIR or "output_data/targets")

    -- Use io.popen to list subdirectories (Love2D has no directory listing for paths
    -- outside the save dir, so we fall back to the OS).
    local handle = io.popen('ls -1 "' .. baseDir .. '" 2>/dev/null')
    if not handle then return end

    for name in handle:lines() do
        local dir = baseDir .. "/" .. name
        -- Only include entries that are directories with a script.txt
        local sf = io.open(dir .. "/script.txt", "r")
        if sf then
            sf:close()
            local hasAudio = io.open(dir .. "/cue_in.mp3", "r") ~= nil
            if hasAudio then
                -- close the file handle we just opened for the check
                -- (io.open returns the handle; we only needed the existence test)
            end
            targets[#targets + 1] = {
                name     = name,
                dir      = dir,
                hasAudio = hasAudio,
            }
        end
    end
    handle:close()
end

function target_select.load()
    fontTitle = love.graphics.newFont(28)
    fontBody  = love.graphics.newFont(18)
    fontHint  = love.graphics.newFont(14)
    selected = 1
    cue_in_status_msg = nil
    scanTargets()

    -- Show a message if a generation is currently running
    local cue_in = require("modules.cue_in")
    if cue_in.getStatus() == "generating" then
        cue_in_status_msg = "Generating cue-in script in background..."
    elseif cue_in.getStatus() == "done" then
        -- Refresh list in case the new target just finished
        scanTargets()
        cue_in.reset()
    end
end

function target_select.update(dt)
    -- Refresh if generation finishes while on this screen
    local cue_in = require("modules.cue_in")
    local s = cue_in.getStatus()
    if s == "done" then
        cue_in_status_msg = nil
        scanTargets()
        cue_in.reset()
    elseif s == "generating" then
        cue_in_status_msg = "Generating cue-in script in background..."
    elseif s == "error" then
        cue_in_status_msg = "Generation error: " .. (cue_in.getError() or "unknown")
    end
end

function target_select.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    love.graphics.setFont(fontTitle)
    love.graphics.setColor(1, 1, 1)
    local title = "Select Target Image"
    love.graphics.print(title, (W - fontTitle:getWidth(title)) / 2, 30)

    if #targets == 0 then
        love.graphics.setFont(fontBody)
        love.graphics.setColor(0.6, 0.6, 0.7)
        local msg = "No targets available yet."
        local msg2 = "Complete a Target Identification session first."
        love.graphics.print(msg,  (W - fontBody:getWidth(msg))  / 2, H / 2 - 20)
        love.graphics.print(msg2, (W - fontBody:getWidth(msg2)) / 2, H / 2 + 10)
    else
        local startY = 110
        local rowH   = 44
        for i, t in ipairs(targets) do
            local y = startY + (i - 1) * rowH
            local label = t.name:gsub("_", " ")
            if not t.hasAudio then
                label = label .. "  [no audio — press R to regenerate]"
            end

            if i == selected then
                -- Highlight bar
                love.graphics.setColor(0.2, 0.35, 0.55, 0.7)
                love.graphics.rectangle("fill", 40, y - 4, W - 80, rowH - 4, 6, 6)
                love.graphics.setColor(1, 1, 1)
            else
                love.graphics.setColor(0.65, 0.75, 0.90)
            end

            love.graphics.setFont(fontBody)
            love.graphics.print("> " .. label, 60, y + 4)
        end
    end

    -- Generation status
    if cue_in_status_msg then
        love.graphics.setFont(fontHint)
        love.graphics.setColor(0.9, 0.8, 0.3)
        local sw = fontHint:getWidth(cue_in_status_msg)
        love.graphics.print(cue_in_status_msg, (W - sw) / 2, H - 64)
    end

    -- Hints
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.4, 0.4, 0.5)
    local hint
    if #targets > 0 then
        hint = "↑↓ Navigate   Enter — Begin session   R — Review/edit script   Escape — Back"
    else
        hint = "T — generate from last transcript   Escape — Back to menu"
    end
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

--- Find the most recent target_image_*.txt in output_data/ and trigger generation.
local function generateFromLastTranscript()
    local dir = love.filesystem.getSource() .. "/" .. (config.AGENT_OUTPUT_DIR or "output_data")
    local handle = io.popen('ls -1t "' .. dir .. '"/target_image_*.txt 2>/dev/null | head -1')
    if not handle then
        cue_in_status_msg = "No transcript files found in output_data/"
        return
    end
    local path = handle:read("*l")
    handle:close()
    if not path or path == "" then
        cue_in_status_msg = "No target_image_*.txt files found."
        return
    end
    local f = io.open(path, "r")
    if not f then
        cue_in_status_msg = "Could not read: " .. path
        return
    end
    local text = f:read("*a")
    f:close()
    local cue_in = require("modules.cue_in")
    cue_in.generate(text)
    cue_in_status_msg = "Generating from: " .. path:match("([^/]+)$")
end

function target_select.keypressed(k)
    if k == "escape" then
        switchScreen("menu")
        return
    end

    -- Dev shortcut: generate a target from the most recent transcript without
    -- needing to run a full TII agent session.
    if k == "t" then
        local cue_in = require("modules.cue_in")
        if cue_in.getStatus() ~= "generating" then
            generateFromLastTranscript()
        end
        return
    end

    if #targets == 0 then return end

    if k == "up" then
        selected = selected - 1
        if selected < 1 then selected = #targets end

    elseif k == "down" then
        selected = selected + 1
        if selected > #targets then selected = 1 end

    elseif k == "return" or k == "kpenter" then
        local t = targets[selected]
        if not t.hasAudio then
            cue_in_status_msg = "No audio yet — press R to review and generate audio first."
            return
        end
        -- Store selected target on the session; the pre-rating screen
        -- starts the session once the SUD rating is confirmed
        session.selectedTargetDir  = t.dir
        session.selectedTargetName = t.name
        switchScreen("pre_rating")

    elseif k == "r" then
        local t = targets[selected]
        session.selectedTargetDir  = t.dir
        session.selectedTargetName = t.name
        switchScreen("cue_in_review")
    end
end

return target_select
