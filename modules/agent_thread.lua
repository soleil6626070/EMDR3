-- modules/agent_thread.lua
-- Worker thread: connects to ElevenLabs Conversational AI via WebSocket,
-- streams user audio, receives agent audio + transcript events.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local controlChannel  = love.thread.getChannel("agent_control")
local audioOutChannel = love.thread.getChannel("agent_audio_out")
local eventsChannel   = love.thread.getChannel("agent_events")
local configChannel   = love.thread.getChannel("agent_config")

-- Receive source path and set up lib/ paths
local sourcePath = configChannel:demand()
package.cpath = sourcePath .. "/lib/?.so;" .. sourcePath .. "/lib/?.dll;" .. package.cpath
package.path  = sourcePath .. "/lib/?.lua;" .. sourcePath .. "/lib/?/init.lua;" .. package.path

local websocket = require("websocket")

----------------------------------------------------------------------
-- Minimal JSON helpers (no external dependency)
----------------------------------------------------------------------

--- Decode a JSON string into a Lua table (handles the subset ElevenLabs sends).
local function json_decode(str)
    if not str or str == "" then return nil end
    -- Use load() with a safe environment to parse JSON-like structures.
    -- JSON maps cleanly to Lua: {} -> table, [] -> table, null -> nil, true/false same.
    local json_str = str
    -- Replace JSON null/true/false
    json_str = json_str:gsub('"([^"]-)":', function(k)
        return '["' .. k .. '"]='
    end)
    json_str = json_str:gsub("%[", "{"):gsub("%]", "}")
    json_str = json_str:gsub(":null", ":nil")

    local fn, err = load("return " .. json_str)
    if not fn then return nil, err end
    -- Run in empty environment for safety
    setfenv(fn, {})
    local ok, result = pcall(fn)
    if not ok then return nil, result end
    return result
end

--- Encode a simple Lua table to JSON (flat key-value, string/number/boolean values only).
local function json_encode(tbl)
    local parts = {}
    for k, v in pairs(tbl) do
        local key = '"' .. tostring(k) .. '"'
        local val
        if type(v) == "string" then
            -- Escape special chars
            val = '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"'
        elseif type(v) == "number" then
            val = tostring(v)
        elseif type(v) == "boolean" then
            val = v and "true" or "false"
        elseif v == nil then
            val = "null"
        else
            val = '"' .. tostring(v) .. '"'
        end
        parts[#parts + 1] = key .. ":" .. val
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

----------------------------------------------------------------------
-- Event helpers
----------------------------------------------------------------------

local function pushEvent(event)
    eventsChannel:push(event)
end

local function pushError(msg)
    pushEvent({ type = "error", message = msg })
end

----------------------------------------------------------------------
-- Main worker logic
----------------------------------------------------------------------

-- Wait for start command
local startCmd = controlChannel:demand()
if startCmd.action ~= "start" then return end

local agent_id = startCmd.agent_id
local api_key  = startCmd.api_key
local base_url = startCmd.base_url or "wss://api.elevenlabs.io"

if not agent_id or agent_id == "" then
    pushError("No agent_id configured")
    return
end

-- Connect WebSocket
local url = base_url .. "/v1/convai/conversation?agent_id=" .. agent_id
local ws, ws_err = websocket.new(url, {
    headers = {
        ["xi-api-key"] = api_key,
    },
    timeout = 15,
})
if not ws then
    pushError("WebSocket create failed: " .. tostring(ws_err))
    return
end

local ok, connect_err = ws:connect()
if not ok then
    pushError("WebSocket connect failed: " .. tostring(connect_err))
    return
end

-- Wait for conversation_initiation_metadata
local init_data, init_opcode = ws:receive(15)
if not init_data then
    pushError("No init metadata received")
    ws:close(1000)
    return
end

local init_msg = json_decode(init_data)
if not init_msg or init_msg.type ~= "conversation_initiation_metadata" then
    pushError("Unexpected init message: " .. tostring(init_data):sub(1, 200))
    ws:close(1000)
    return
end

local meta = init_msg.conversation_initiation_metadata_event or {}
local conversation_id = meta.conversation_id or "unknown"
local output_format = meta.agent_output_audio_format or "pcm_16000"
local input_format  = meta.user_input_audio_format or "pcm_16000"

-- Parse sample rate from format string like "pcm_16000"
local output_rate = tonumber(output_format:match("(%d+)")) or 16000

pushEvent({
    type = "connected",
    conversation_id = conversation_id,
    sample_rate = output_rate,
})

-- Main loop: non-blocking receive from WebSocket + check for audio/control from main thread
local running = true

while running do
    -- Check control channel (non-blocking)
    local ctrl = controlChannel:pop()
    if ctrl then
        if ctrl.action == "stop" or ctrl.action == "quit" then
            running = false
            break
        end
    end

    -- Send any queued user audio to the WebSocket
    while true do
        local audioChunk = audioOutChannel:pop()
        if not audioChunk then break end
        local b64 = love.data.encode("string", "base64", audioChunk)
        local msg = json_encode({ user_audio_chunk = b64 })
        local send_ok, send_err = ws:send(msg, "text")
        if not send_ok then
            pushError("Failed to send audio: " .. tostring(send_err))
            running = false
            break
        end
    end

    if not running then break end

    -- Receive from WebSocket (short timeout for non-blocking behavior)
    local data, opcode = ws:receive(0.05)

    if data and opcode == "text" then
        local msg = json_decode(data)
        if msg then
            if msg.type == "user_transcript" then
                local ev = msg.user_transcription_event or {}
                pushEvent({ type = "user_transcript", text = ev.user_transcript or "" })

            elseif msg.type == "agent_response" then
                local ev = msg.agent_response_event or {}
                pushEvent({ type = "agent_response", text = ev.agent_response or "" })

            elseif msg.type == "agent_response_correction" then
                local ev = msg.agent_response_correction_event or {}
                pushEvent({
                    type = "agent_response_correction",
                    original = ev.original_agent_response or "",
                    corrected = ev.corrected_agent_response or "",
                })

            elseif msg.type == "audio" then
                local ev = msg.audio_event or {}
                if ev.audio_base_64 then
                    local pcm = love.data.decode("string", "base64", ev.audio_base_64)
                    pushEvent({ type = "audio", data = pcm })
                end

            elseif msg.type == "interruption" then
                pushEvent({ type = "interruption" })

            elseif msg.type == "ping" then
                local ev = msg.ping_event or {}
                local pong = json_encode({ type = "pong", event_id = ev.event_id or 0 })
                ws:send(pong, "text")

            elseif msg.type == "conversation_ended" or msg.type == "close" then
                running = false
            end
        end

    elseif data and opcode == "close" then
        running = false

    elseif not data and opcode ~= "timeout" and opcode ~= nil then
        -- Connection error
        pushError("WebSocket receive error: " .. tostring(opcode))
        running = false
    end
end

-- Clean close
pcall(function() ws:close(1000, "client closing") end)
pushEvent({ type = "closed" })
