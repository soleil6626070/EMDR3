-- modules/transcription_thread.lua
-- Worker thread: receives jobs on the request channel, runs whisper-cli, and
-- writes results into the per-session JSON record (see modules/session_json.lua).
-- This thread is the single writer of session record files — the main thread
-- routes its rating writes here as "merge_record" messages so all writes to a
-- record are serialized in channel order.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local requestChannel = love.thread.getChannel("transcription_request")
local statusChannel  = love.thread.getChannel("transcription_status")
local configChannel  = love.thread.getChannel("transcription_config")

-- Receive config: { whisper_bin, whisper_model, source_path, output_dir }
local cfg = configChannel:demand()
local whisperBin   = cfg.whisper_bin
local whisperModel = cfg.whisper_model
local outputDir    = cfg.output_dir

-- Threads get a fresh Lua state, so re-add the project paths before requiring
-- shared modules (lib/json.lua, modules/session_json.lua).
package.path = cfg.source_path .. "/lib/?.lua;"
            .. cfg.source_path .. "/?.lua;" .. package.path
local session_json = require("modules.session_json")

--- Transcribe one WAV and insert the text into its session record.
local function handleTranscribeJob(req)
    local file_path  = req.file_path
    local cycle      = req.cycle
    local session_id = req.session_id

    -- Use a temp file for whisper output
    local tmpBase = os.tmpname()
    local cmd = string.format(
        '%s -m %s -f "%s" --no-timestamps -l en -np -otxt -of "%s" 2>/dev/null',
        whisperBin, whisperModel, file_path, tmpBase
    )

    local exitCode = os.execute(cmd)
    local success = (exitCode == true or exitCode == 0)
    local text = nil

    if success then
        local txtPath = tmpBase .. ".txt"
        local f = io.open(txtPath, "r")
        if f then
            text = f:read("*a")
            f:close()
            os.remove(txtPath)
            -- Trim whitespace
            if text then
                text = text:match("^%s*(.-)%s*$") or ""
            end
        else
            success = false
        end
    end

    -- Clean up temp base file (whisper may or may not create it)
    os.remove(tmpBase)

    if success and text and text ~= "" then
        -- Fallback path covers WAVs recovered from sessions that predate
        -- per-target session records.
        local recordPath = req.record_path
            or (outputDir .. "/session_" .. session_id .. ".json")
        session_json.upsertResponse(recordPath, session_id, cycle, text)

        -- Delete the WAV file after successful transcription + save
        os.remove(file_path)
    else
        print("[TranscriptionThread] Failed for " .. tostring(file_path)
            .. " — preserving WAV for retry")
    end

    statusChannel:push({
        session_id = session_id,
        cycle      = cycle,
        success    = success,
    })
end

while true do
    local req = requestChannel:demand()

    -- Sentinel value to shut down the thread
    if req == "quit" then break end

    if req.type == "merge_record" then
        -- Rating/metadata write routed from the main thread. No status push:
        -- pending/completed counters only track transcription jobs.
        session_json.merge(req.record_path, req.fields)
    else
        handleTranscribeJob(req)
    end
end
