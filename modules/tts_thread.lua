-- modules/tts_thread.lua
-- Worker thread: receives TTS requests, POSTs to ElevenLabs, returns audio bytes.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local requestChannel  = love.thread.getChannel("tts_request")
local responseChannel = love.thread.getChannel("tts_response")
local configChannel   = love.thread.getChannel("tts_config")

-- Receive the source path so we can find lib/https.so
local sourcePath = configChannel:demand()
package.cpath = sourcePath .. "/lib/?.so;" .. sourcePath .. "/lib/?.dll;" .. package.cpath

local https = require("https")

while true do
    -- Block until a request arrives
    local req = requestChannel:demand()

    -- Sentinel value to shut down the thread
    if req == "quit" then break end

    local request_id = req.request_id
    local text       = req.text
    local voice_id   = req.voice_id
    local api_key    = req.api_key
    local base_url   = req.base_url
    local model_id   = req.model_id
    local speed      = req.speed or 1.0

    local url = base_url .. "/text-to-speech/" .. voice_id

    -- Build JSON body (simple escaping for now)
    local escaped_text = text:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
    local body = string.format(
        '{"text":"%s","model_id":"%s","voice_settings":{"stability":0.5,"similarity_boost":0.75,"speed":%.1f}}',
        escaped_text, model_id, speed
    )

    local code, responseBody, headers = https.request(url, {
        method  = "POST",
        headers = {
            ["Accept"]       = "audio/mpeg",
            ["Content-Type"] = "application/json",
            ["xi-api-key"]   = api_key,
        },
        data = body,
    })

    if code == 200 then
        responseChannel:push({
            request_id = request_id,
            success    = true,
            code       = code,
            data       = responseBody,
        })
    else
        responseChannel:push({
            request_id = request_id,
            success    = false,
            code       = code,
            error      = "HTTP " .. tostring(code) .. ": " .. tostring(responseBody),
        })
    end
end
