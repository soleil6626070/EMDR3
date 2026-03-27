-- modules/agent.lua
-- Main-thread API for the ElevenLabs Conversational AI agent.
-- Screens call agent.start() / agent.stop(); poll agent.update() each frame.

local agent = {}

local thread
local controlChannel
local audioOutChannel
local eventsChannel
local configChannel

local config
local status = "idle"       -- "idle" | "connecting" | "listening" | "speaking" | "error" | "finished"
local transcript = {}       -- { {role="agent"|"user", text="..."}, ... }
local errorMsg = nil
local active = false
local conversationId = nil

-- Audio playback state
local playbackQueue = {}    -- queue of raw PCM strings from agent
local currentSource = nil   -- love.audio Source currently playing
local sampleRate = 16000    -- default, updated from conversation_initiation_metadata

function agent.init(cfg)
    config = cfg

    controlChannel  = love.thread.getChannel("agent_control")
    audioOutChannel = love.thread.getChannel("agent_audio_out")
    eventsChannel   = love.thread.getChannel("agent_events")
    configChannel   = love.thread.getChannel("agent_config")
end

--- Start a conversation with the ElevenLabs agent.
function agent.start()
    if active then return end

    -- Reset state
    status = "connecting"
    transcript = {}
    errorMsg = nil
    playbackQueue = {}
    currentSource = nil
    conversationId = nil
    active = true

    -- Start worker thread
    thread = love.thread.newThread("modules/agent_thread.lua")
    configChannel:push(love.filesystem.getSource())
    controlChannel:push({
        action   = "start",
        agent_id = config.ELEVENLABS_AGENT_ID,
        api_key  = config.ELEVENLABS_API_KEY,
        base_url = config.ELEVENLABS_WS_URL or "wss://api.elevenlabs.io",
    })
    thread:start()
end

--- Send a chunk of raw PCM audio (16-bit mono, 16kHz) to the agent.
function agent.sendAudio(pcmData)
    if not active then return end
    audioOutChannel:push(pcmData)
end

--- Poll for events from the worker thread. Call every frame from love.update(dt).
function agent.update()
    if not thread then return end

    -- Check for thread errors
    local err = thread:getError()
    if err then
        print("[Agent] Thread error: " .. err)
        status = "error"
        errorMsg = err
        active = false
    end

    -- Pop all events from worker
    while true do
        local event = eventsChannel:pop()
        if not event then break end

        if event.type == "connected" then
            status = "listening"
            conversationId = event.conversation_id
            sampleRate = event.sample_rate or 16000

        elseif event.type == "user_transcript" then
            transcript[#transcript + 1] = { role = "user", text = event.text }

        elseif event.type == "agent_response" then
            status = "speaking"
            transcript[#transcript + 1] = { role = "agent", text = event.text }

        elseif event.type == "agent_response_correction" then
            -- Find and correct the last agent response
            for i = #transcript, 1, -1 do
                if transcript[i].role == "agent" and transcript[i].text == event.original then
                    transcript[i].text = event.corrected
                    break
                end
            end

        elseif event.type == "audio" then
            playbackQueue[#playbackQueue + 1] = event.data

        elseif event.type == "interruption" then
            -- Stop playing agent audio
            if currentSource then
                currentSource:stop()
                currentSource = nil
            end
            playbackQueue = {}
            status = "listening"

        elseif event.type == "agent_listening" then
            status = "listening"

        elseif event.type == "error" then
            status = "error"
            errorMsg = event.message
            active = false

        elseif event.type == "closed" then
            status = "finished"
            active = false
        end
    end

    -- Audio playback: if nothing is playing, dequeue next chunk
    if currentSource and not currentSource:isPlaying() then
        currentSource = nil
    end

    if not currentSource and #playbackQueue > 0 then
        local pcmData = table.remove(playbackQueue, 1)
        local samples = #pcmData / 2  -- 16-bit = 2 bytes per sample
        if samples > 0 then
            local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)
            -- Copy raw PCM bytes into SoundData
            local ffi = require("ffi")
            local ptr = soundData:getFFIPointer()
            ffi.copy(ptr, pcmData, #pcmData)
            currentSource = love.audio.newSource(soundData)
            currentSource:play()
        end
    end

    -- Update status based on playback state
    if active and status == "speaking" and not currentSource and #playbackQueue == 0 then
        status = "listening"
    end
end

--- Stop the conversation.
function agent.stop()
    if not active then return end
    controlChannel:push({ action = "stop" })
    -- Stop any playing audio
    if currentSource then
        currentSource:stop()
        currentSource = nil
    end
    playbackQueue = {}
end

--- Shut down the worker thread. Call from love.quit().
function agent.shutdown()
    if thread and thread:isRunning() then
        controlChannel:push({ action = "quit" })
        thread:wait()
    end
end

--- Get current agent status.
function agent.getStatus()
    return status
end

--- Get the conversation transcript.
function agent.getTranscript()
    return transcript
end

--- Is a conversation currently active?
function agent.isActive()
    return active
end

--- Get error message (if status == "error").
function agent.getError()
    return errorMsg
end

--- Get conversation ID.
function agent.getConversationId()
    return conversationId
end

--- Reset state (for starting a new conversation later).
function agent.reset()
    status = "idle"
    transcript = {}
    errorMsg = nil
    active = false
    conversationId = nil
    playbackQueue = {}
    currentSource = nil
end

return agent
