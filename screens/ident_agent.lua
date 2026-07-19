-- screens/ident_agent.lua
-- The live agent call, narrowed to negotiating the target image. Streams the
-- mic to the ElevenLabs agent (16 kHz PCM, as the legacy screen did); when the
-- call ends, the raw transcript is saved to output_data/ FIRST (a completed
-- call can never be lost), then one extraction LLM call produces
-- {slug, image, confirmed} and identification.beginTarget makes the flow
-- durable. A dropped/errored call is not resumable — R restarts it.

local config         = require("config")
local agent          = require("modules.agent")
local identification = require("modules.identification")
local extraction     = require("modules.extraction")

local ident_agent = {}

local AUDIO_SEND_INTERVAL = 0.1

local phase   -- "call" | "extracting" | "call_failed" | "extract_failed"
local mic
local elapsed, audioSendTimer, pulseTimer
local errorText
local transcriptContent   -- header + lines, written to the target dir on success
local extractionResult    -- set by the extraction callback, consumed in update
local screenAlive
local fontTitle, fontBody, fontHint
local bgShader, shaderTime, spinTime

local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

----------------------------------------------------------------------
-- Mic streaming (16 kHz mono to match the agent's expected input)
----------------------------------------------------------------------

local function startMic()
    local devices = love.audio.getRecordingDevices()
    if devices and #devices > 0 then
        mic = devices[1]
        mic:start(16000 * 60, 16000, 16, 1)  -- ~60s buffer
    else
        mic = nil
        print("[IdentAgent] No microphone found")
    end
end

local function stopMic()
    if mic and mic:isRecording() then mic:stop() end
    mic = nil
end

--- mic:getData() returns only the samples since the previous call and clears
--- the ring buffer, so each chunk is exactly the new audio.
local function streamMicAudio()
    if not mic or not mic:isRecording() then return end
    local soundData = mic:getData()
    if not soundData then return end
    local sampleCount = soundData:getSampleCount()
    if sampleCount == 0 then return end

    local ffi = require("ffi")
    local ptr = soundData:getFFIPointer()
    agent.sendAudio(ffi.string(ffi.cast("char*", ptr), sampleCount * 2))
end

----------------------------------------------------------------------
-- Transcript + extraction
----------------------------------------------------------------------

--- Serialize the conversation and write it to output_data/ before anything
--- else can fail. Returns the content (reused for the target dir copy).
local function saveRawTranscript()
    local transcript = agent.getTranscript()
    local lines = {
        "Target Identification (image only)",
        "Date: " .. os.date("%Y-%m-%d %H:%M:%S"),
    }
    local convId = agent.getConversationId()
    if convId then lines[#lines + 1] = "Conversation ID: " .. convId end
    lines[#lines + 1] = "===== RAW TRANSCRIPT ====="
    for _, msg in ipairs(transcript) do
        lines[#lines + 1] = (msg.role == "user" and "User: " or "Agent: ") .. (msg.text or "")
    end
    lines[#lines + 1] = "===== END OF TRANSCRIPT ====="
    local content = table.concat(lines, "\n") .. "\n"

    local dir = love.filesystem.getSource() .. "/" .. (config.AGENT_OUTPUT_DIR or "output_data")
    os.execute('mkdir -p "' .. dir .. '"')
    local path = dir .. "/target_image_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
    else
        print("[IdentAgent] WARNING: could not save transcript to " .. path)
    end
    return content
end

local function startExtraction()
    phase = "extracting"
    extraction.run(agent.getTranscript(), function(ok, result, err)
        if not screenAlive then return end
        extractionResult = { ok = ok, result = result, err = err }
    end)
end

local function handleCallEnded()
    stopMic()
    local transcript = agent.getTranscript()
    if #transcript == 0 then
        phase = "call_failed"
        errorText = "The call ended before any conversation happened."
        return
    end
    transcriptContent = saveRawTranscript()
    startExtraction()
end

local function handleExtraction(res)
    if not res.ok then
        phase = "extract_failed"
        errorText = tostring(res.err)
        return
    end

    local dir = identification.beginTarget({
        slug            = res.result.slug,
        image           = res.result.image,
        confirmed       = res.result.confirmed,
        conversation_id = agent.getConversationId(),
    })

    -- Target-folder copy of the transcript (target_select/cue-in expect it)
    local f = io.open(dir .. "/transcript.txt", "w")
    if f then f:write(transcriptContent or ""); f:close() end

    screenAlive = false
    agent.reset()
    identification.advance()   -- image step done → negative cognition
end

----------------------------------------------------------------------
-- Screen callbacks
----------------------------------------------------------------------

function ident_agent.load()
    phase            = "call"
    elapsed          = 0
    audioSendTimer   = 0
    pulseTimer       = 0
    errorText        = nil
    transcriptContent = nil
    extractionResult = nil
    screenAlive      = true

    fontTitle = love.graphics.newFont(28)
    fontBody  = love.graphics.newFont(18)
    fontHint  = love.graphics.newFont(14)
    bgShader  = love.graphics.newShader("resources/shaders/background.fs")
    shaderTime, spinTime = 0, 0

    startMic()
    agent.start()
end

function ident_agent.update(dt)
    pulseTimer = pulseTimer + dt
    local mult = (phase == "extracting") and 3.0 or 1.0
    shaderTime = shaderTime + dt * mult
    spinTime   = spinTime + dt * 0.1 * mult

    if phase == "call" then
        elapsed = elapsed + dt

        if agent.isActive() then
            audioSendTimer = audioSendTimer + dt
            if audioSendTimer >= AUDIO_SEND_INTERVAL then
                audioSendTimer = 0
                streamMicAudio()
            end
            -- Local safety net only: the server cap (max_duration_seconds) is
            -- lower and fires first with a graceful conversation end.
            if config.AGENT_MAX_DURATION and elapsed >= config.AGENT_MAX_DURATION then
                agent.stop()
                stopMic()
            end
        end

        -- Backstop: never leave the mic recording once the call is over,
        -- even if the worker wedges without a clean "closed" event
        if not agent.isActive() and mic then
            stopMic()
        end

        local status = agent.getStatus()
        if status == "finished" then
            handleCallEnded()
        elseif status == "error" then
            stopMic()
            phase = "call_failed"
            errorText = tostring(agent.getError())
        end

    elseif phase == "extracting" then
        if extractionResult then
            local res = extractionResult
            extractionResult = nil
            handleExtraction(res)
        end
    end
end

function ident_agent.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    bgShader:send("time", shaderTime)
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

    love.graphics.setFont(fontTitle)
    love.graphics.setColor(1, 1, 1)

    local hint = "Escape — end call & back to menu"

    if phase == "call" then
        local status = agent.getStatus()
        local text, dotColor
        if status == "connecting" then
            text, dotColor = "Connecting...", {0.9, 0.8, 0.3}
        elseif status == "speaking" then
            text, dotColor = "", {0.3, 0.8, 0.9}
        else
            text, dotColor = "", {0.4, 0.9, 0.4}
        end
        if text ~= "" then
            love.graphics.printf(text, W * 0.15, H * 0.35, W * 0.7, "center")
        end
        -- Soft pulsing presence dot — the guide is "there" without words
        local pulse = 0.55 + 0.45 * math.sin(pulseTimer * 2)
        love.graphics.setColor(dotColor[1], dotColor[2], dotColor[3], pulse * 0.8)
        love.graphics.circle("fill", W / 2, H * 0.55, 14)
        if not mic then
            love.graphics.setFont(fontBody)
            love.graphics.setColor(1.0, 0.75, 0.35)
            local warn = "No microphone detected — the guide cannot hear you"
            love.graphics.print(warn, (W - fontBody:getWidth(warn)) / 2, H * 0.7)
        end

    elseif phase == "extracting" then
        love.graphics.printf("Holding onto your image...", W * 0.15, H * 0.4, W * 0.7, "center")
        hint = "Escape — cancel & back to menu"

    elseif phase == "call_failed" or phase == "extract_failed" then
        local title = phase == "call_failed" and "The call didn't complete."
                                             or "Couldn't capture the image from the call."
        love.graphics.printf(title, W * 0.15, H * 0.35, W * 0.7, "center")
        love.graphics.setFont(fontBody)
        love.graphics.setColor(0.9, 0.6, 0.5)
        love.graphics.printf(errorText or "", W * 0.2, H * 0.48, W * 0.6, "center")
        if phase == "extract_failed" then
            love.graphics.setColor(0.75, 0.82, 0.95)
            love.graphics.printf("Your conversation is saved — nothing is lost.",
                W * 0.2, H * 0.58, W * 0.6, "center")
            hint = "R — retry   Escape — back to menu"
        else
            hint = "R — call again   Escape — back to menu"
        end
    end

    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.75, 0.82, 0.95, 0.8)
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

function ident_agent.keypressed(k)
    if k == "escape" then
        screenAlive = false
        if agent.isActive() then agent.stop() end
        stopMic()
        agent.reset()
        identification.reset()
        switchScreen("menu")
        return
    end

    if k == "r" then
        if phase == "call_failed" then
            agent.reset()
            ident_agent.load()          -- fresh call
        elseif phase == "extract_failed" then
            startExtraction()           -- transcript still in agent module
        end
    end
end

return ident_agent
