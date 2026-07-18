-- screens/target_identification.lua
-- Conversation UI for ElevenLabs agent-based target identification.
-- Captures mic audio, streams to agent, displays status + live transcript.

local agent   = require("modules.agent")
local cue_in  = require("modules.cue_in")
local config  = require("config")

local tid = {}

local fontTitle, fontBody, fontHint
local mic
local elapsed = 0
local audioSendTimer = 0
local AUDIO_SEND_INTERVAL = 0.1  -- send mic chunks every 100ms

-- Transcript scroll
local scrollOffset = 0
local maxScroll = 0

--- Write transcript to output file.
local function writeTranscript()
    local transcript = agent.getTranscript()
    if #transcript == 0 then return nil end

    local projectRoot = love.filesystem.getSource()
    local outDir = projectRoot .. "/" .. config.AGENT_OUTPUT_DIR
    os.execute('mkdir -p "' .. outDir .. '"')

    local timestamp = os.date("%Y%m%d_%H%M%S")
    local filename = "target_image_" .. timestamp .. ".txt"
    local filepath = outDir .. "/" .. filename

    -- Build content string (used both for file and for passing to cue_in.generate)
    local lines = {}
    lines[#lines+1] = "Target Identification"
    lines[#lines+1] = "Date: " .. os.date("%Y-%m-%d %H:%M:%S")
    local conv_id = agent.getConversationId()
    if conv_id then
        lines[#lines+1] = "Conversation ID: " .. conv_id
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "===== RAW TRANSCRIPT ====="
    lines[#lines+1] = ""
    for _, entry in ipairs(transcript) do
        local role = entry.role == "agent" and "Agent" or "User"
        lines[#lines+1] = role .. ": " .. entry.text
    end
    lines[#lines+1] = ""
    lines[#lines+1] = "===== END OF TRANSCRIPT ====="
    local content = table.concat(lines, "\n") .. "\n"

    local f = io.open(filepath, "w")
    if not f then
        print("[TID] Failed to write: " .. filepath)
        return nil
    end
    f:write(content)
    f:close()

    print("[TID] Transcript saved: " .. filepath)
    return filepath, content
end

--- Start mic recording at 16kHz for streaming to agent.
local function startMic()
    local devices = love.audio.getRecordingDevices()
    if devices and #devices > 0 then
        mic = devices[1]
        -- Large buffer, 16kHz mono 16-bit to match ElevenLabs expected input
        mic:start(16000 * 60, 16000, 16, 1)  -- ~60s buffer
    else
        mic = nil
        print("[TID] No microphone found")
    end
end

--- Stop mic recording.
local function stopMic()
    if mic and mic:isRecording() then
        mic:stop()
    end
    mic = nil
end

--- Read new mic samples and send to agent as raw PCM chunks.
-- mic:getData() returns ONLY the samples recorded since the previous call and
-- clears the device's ring buffer, so each call's SoundData is already the new
-- audio — send the whole thing (no manual offset tracking).
local function streamMicAudio()
    if not mic or not mic:isRecording() then return end

    local soundData = mic:getData()
    if not soundData then return end

    local sampleCount = soundData:getSampleCount()
    if sampleCount == 0 then return end

    -- Raw 16-bit mono PCM: 2 bytes per sample.
    local ffi = require("ffi")
    local ptr = soundData:getFFIPointer()
    local pcmChunk = ffi.string(ffi.cast("char*", ptr), sampleCount * 2)
    agent.sendAudio(pcmChunk)
end

function tid.load()
    fontTitle = love.graphics.newFont(28)
    fontBody  = love.graphics.newFont(16)
    fontHint  = love.graphics.newFont(14)
    elapsed = 0
    audioSendTimer = 0
    scrollOffset = 0

    startMic()
    agent.start()
end

function tid.update(dt)
    elapsed = elapsed + dt
    agent.update()

    -- Stream mic audio at regular intervals
    if agent.isActive() then
        audioSendTimer = audioSendTimer + dt
        if audioSendTimer >= AUDIO_SEND_INTERVAL then
            audioSendTimer = 0
            streamMicAudio()
        end

        -- Safety timeout
        if config.AGENT_MAX_DURATION and elapsed >= config.AGENT_MAX_DURATION then
            agent.stop()
            stopMic()
        end
    end

    -- Auto-stop mic when conversation ends
    if not agent.isActive() and mic then
        stopMic()
    end
end

function tid.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
    love.graphics.clear()

    -- Title
    love.graphics.setFont(fontTitle)
    love.graphics.setColor(1, 1, 1)
    local title = "Target Identification"
    local titleW = fontTitle:getWidth(title)
    love.graphics.print(title, (W - titleW) / 2, 30)

    -- Status indicator
    local status = agent.getStatus()
    local statusText, dotR, dotG, dotB

    if status == "connecting" then
        statusText = "Connecting..."
        dotR, dotG, dotB = 0.8, 0.7, 0.2
    elseif status == "listening" then
        statusText = "Listening..."
        dotR, dotG, dotB = 0.2, 0.8, 0.3
    elseif status == "speaking" then
        statusText = "Speaking..."
        dotR, dotG, dotB = 0.3, 0.5, 0.9
    elseif status == "error" then
        statusText = "Error: " .. (agent.getError() or "unknown")
        dotR, dotG, dotB = 0.9, 0.2, 0.2
    elseif status == "finished" then
        statusText = "Conversation complete"
        dotR, dotG, dotB = 0.5, 0.5, 0.5
    else
        statusText = "Idle"
        dotR, dotG, dotB = 0.4, 0.4, 0.4
    end

    -- Pulsing dot
    local pulse = 0.6 + 0.4 * math.sin(elapsed * 3)
    love.graphics.setColor(dotR, dotG, dotB, pulse)
    love.graphics.circle("fill", W / 2 - 90, 85, 8)

    love.graphics.setFont(fontBody)
    love.graphics.setColor(dotR, dotG, dotB)
    love.graphics.print(statusText, W / 2 - 70, 77)

    -- Transcript area
    local txArea = { x = 40, y = 120, w = W - 80, h = H - 180 }

    -- Background for transcript area
    love.graphics.setColor(0.08, 0.08, 0.10, 0.8)
    love.graphics.rectangle("fill", txArea.x, txArea.y, txArea.w, txArea.h, 8, 8)

    -- Clip transcript to area
    love.graphics.setScissor(txArea.x, txArea.y, txArea.w, txArea.h)

    local transcript = agent.getTranscript()
    local y = txArea.y + 10 - scrollOffset
    local lineHeight = fontBody:getHeight() + 4
    local wrapWidth = txArea.w - 20

    love.graphics.setFont(fontBody)
    for _, entry in ipairs(transcript) do
        local prefix = entry.role == "agent" and "Agent: " or "You: "
        local text = prefix .. entry.text
        local _, lines = fontBody:getWrap(text, wrapWidth)
        local blockHeight = #lines * lineHeight

        if entry.role == "agent" then
            love.graphics.setColor(0.6, 0.75, 0.95)
        else
            love.graphics.setColor(0.85, 0.85, 0.85)
        end

        love.graphics.printf(text, txArea.x + 10, y, wrapWidth)
        y = y + blockHeight + 8
    end

    -- Calculate max scroll
    local contentHeight = y + scrollOffset - txArea.y - 10
    maxScroll = math.max(0, contentHeight - txArea.h)

    -- Auto-scroll to bottom when new content arrives
    if maxScroll > 0 then
        scrollOffset = maxScroll
    end

    love.graphics.setScissor()

    -- Hints
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.4, 0.4, 0.5)
    if agent.isActive() then
        local hint = "Escape — end conversation"
        local hintW = fontHint:getWidth(hint)
        love.graphics.print(hint, (W - hintW) / 2, H - 40)
    else
        local hint = "Escape — return to menu"
        if status == "finished" then
            hint = "Enter — save & return to menu    Escape — discard & return"
        end
        local hintW = fontHint:getWidth(hint)
        love.graphics.print(hint, (W - hintW) / 2, H - 40)
    end
end

function tid.keypressed(k)
    if k == "escape" then
        if agent.isActive() then
            agent.stop()
            stopMic()
        else
            -- Discard and return to menu
            agent.reset()
            switchScreen("menu")
        end
    elseif k == "return" or k == "kpenter" then
        if not agent.isActive() then
            local _, transcriptText = writeTranscript()
            if transcriptText then
                cue_in.generate(transcriptText)
            end
            agent.reset()
            switchScreen("menu")
        end
    end
end

return tid
