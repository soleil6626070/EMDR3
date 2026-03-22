local session = require("modules.session")
local wav = require("modules.wav")

local noticed = {}

local source
local font, hintFont
local phase          -- "playing", "recording", "done"
local mic
local recordingData
local pulseTimer

function noticed.load()
    phase = "playing"
    mic = nil
    recordingData = nil
    pulseTimer = 0

    font = love.graphics.newFont(36)
    hintFont = love.graphics.newFont(14)

    -- Pick from all files in the wdyn folder
    local variants = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems("resources/audio/wdyn")) do
        table.insert(variants, "resources/audio/wdyn/" .. name)
    end

    -- Pick a random variant and play it
    if #variants > 0 then
        local pick = variants[love.math.random(#variants)]
        source = love.audio.newSource(pick, "static")
        source:play()
    else
        -- No audio files found — go straight to recording
        source = nil
        noticed._startRecording()
    end
end

function noticed._startRecording()
    phase = "recording"
    pulseTimer = 0

    local devices = love.audio.getRecordingDevices()
    if devices and #devices > 0 then
        mic = devices[1]
        -- ~23s mono buffer at 44100 Hz, 16-bit
        mic:start(1024 * 1024, 44100, 16, 1)
    else
        mic = nil
    end
end

function noticed._stopAndSave()
    if mic and mic:isRecording() then
        recordingData = mic:stop()
        if recordingData and recordingData:getSampleCount() > 0 then
            local projectRoot = love.filesystem.getSource()
            local outDir = projectRoot .. "/resources/audio/user_responses"
            os.execute('mkdir -p "' .. outDir .. '"')

            local outPath = projectRoot .. "/" .. session.getResponseFilename()
            local encoded = wav.encode(recordingData)
            local f = io.open(outPath, "wb")
            if f then
                f:write(encoded)
                f:close()
            end
        end
    end
end

function noticed._advance()
    if session.isLastCycle() then
        session.reset()
        switchScreen("menu")
    else
        switchScreen("notice_that")
    end
end

function noticed.update(dt)
    if phase == "playing" then
        if source and not source:isPlaying() then
            noticed._startRecording()
        end
    elseif phase == "recording" then
        pulseTimer = pulseTimer + dt
    end
end

function noticed.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    if phase == "playing" then
        -- Centered prompt text
        love.graphics.setFont(font)
        love.graphics.setColor(1, 1, 1)
        local text = "What did you notice?"
        local textW = font:getWidth(text)
        love.graphics.print(text, (W - textW) / 2, H / 2 - font:getHeight() / 2)
    elseif phase == "recording" then
        love.graphics.setFont(font)
        if mic then
            -- Recording indicator: pulsing red dot
            local pulse = 0.5 + 0.5 * math.sin(pulseTimer * 4)
            local dotRadius = 10
            love.graphics.setColor(0.9, 0.1, 0.1, pulse)
            love.graphics.circle("fill", W / 2 - 80, H / 2, dotRadius)

            -- "Recording..." text
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("Recording...", W / 2 - 60, H / 2 - font:getHeight() / 2)
        else
            love.graphics.setColor(1, 1, 1)
            local text = "What did you notice?"
            local textW = font:getWidth(text)
            love.graphics.print(text, (W - textW) / 2, H / 2 - font:getHeight() / 2)
        end
    end

    -- Hint
    love.graphics.setFont(hintFont)
    love.graphics.setColor(0.3, 0.3, 0.4)
    if phase == "recording" then
        if mic then
            love.graphics.print("Space/Enter — stop recording   Escape — discard & menu", 20, H - 36)
        else
            love.graphics.print("Space/Enter — continue   Escape — menu", 20, H - 36)
        end
    else
        love.graphics.print("Escape — return to menu", 20, H - 36)
    end
end

function noticed.keypressed(k)
    if k == "escape" then
        if source then source:stop() end
        if mic and mic:isRecording() then mic:stop() end
        session.reset()
        switchScreen("menu")
    elseif phase == "recording" and (k == "space" or k == "return" or k == "kpenter") then
        noticed._stopAndSave()
        noticed._advance()
    end
end

return noticed
