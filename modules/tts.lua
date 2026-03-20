-- modules/tts.lua
-- Main-thread TTS API. Screens call tts.speak(text, opts, callback).

local tts = {}

local thread
local requestChannel
local responseChannel
local configChannel
local callbacks = {}
local nextId = 1
local config

function tts.init(cfg)
    config = cfg

    -- Ensure audio output directory exists in the Love2D save directory
    love.filesystem.createDirectory("audio")

    requestChannel  = love.thread.getChannel("tts_request")
    responseChannel = love.thread.getChannel("tts_response")
    configChannel   = love.thread.getChannel("tts_config")

    thread = love.thread.newThread("modules/tts_thread.lua")
    -- Send the source path so the thread can find lib/https.so
    configChannel:push(love.filesystem.getSource())
    thread:start()
end

--- Request TTS generation.
-- @param text     The text to speak
-- @param opts     Optional table: { voice_id = "...", model_id = "..." }
-- @param callback function(success, source_or_nil, error_or_nil)
function tts.speak(text, opts, callback)
    opts = opts or {}

    local id = nextId
    nextId = nextId + 1

    callbacks[id] = callback

    requestChannel:push({
        request_id = id,
        text       = text,
        voice_id   = opts.voice_id or config.ELEVENLABS_VOICE_ID,
        api_key    = config.ELEVENLABS_API_KEY,
        base_url   = config.ELEVENLABS_BASE_URL,
        model_id   = opts.model_id or config.ELEVENLABS_MODEL_ID,
    })
end

--- Call every frame from love.update(dt). Pops completed responses and fires callbacks.
function tts.update()
    -- Check for thread errors
    local err = thread:getError()
    if err then
        print("[TTS] Thread error: " .. err)
    end

    -- Pop all available responses
    while true do
        local resp = responseChannel:pop()
        if not resp then break end

        local cb = callbacks[resp.request_id]
        callbacks[resp.request_id] = nil

        if resp.success then
            -- Save mp3 to Love2D save directory and create audio source
            local filename = "audio/tts_" .. resp.request_id .. ".mp3"
            love.filesystem.write(filename, resp.data)
            local source = love.audio.newSource(filename, "static")
            if cb then cb(true, source, nil) end
        else
            print("[TTS] API error: " .. tostring(resp.error))
            if cb then cb(false, nil, resp.error) end
        end
    end
end

function tts.shutdown()
    if thread and thread:isRunning() then
        requestChannel:push("quit")
        thread:wait()
    end
end

return tts
