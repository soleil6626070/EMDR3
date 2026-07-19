-- modules/transcription_thread.lua
-- Worker thread: pure transcription. Receives WAV jobs, runs whisper-cli, and
-- pushes the resulting text back over the status channel. It never touches
-- session record files or deletes WAVs — the main thread does both when the
-- result arrives (see modules/transcription.lua), so record files have exactly
-- one writer and a queued result can never race a rating write.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local requestChannel = love.thread.getChannel("transcription_request")
local statusChannel  = love.thread.getChannel("transcription_status")
local configChannel  = love.thread.getChannel("transcription_config")

-- Receive config: { whisper_bin, whisper_model, source_path, output_dir }
local cfg = configChannel:demand()
local whisperBin   = cfg.whisper_bin
local whisperModel = cfg.whisper_model

while true do
    local req = requestChannel:demand()

    -- Sentinel value to shut down the thread
    if req == "quit" then break end

    -- Use a temp file for whisper output
    local tmpBase = os.tmpname()
    local cmd = string.format(
        '%s -m %s -f "%s" --no-timestamps -l en -np -otxt -of "%s" 2>/dev/null',
        whisperBin, whisperModel, req.file_path, tmpBase
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

    statusChannel:push({
        session_id  = req.session_id,
        cycle       = req.cycle,
        file_path   = req.file_path,
        record_path = req.record_path,
        job_id      = req.job_id,
        success     = success,
        text        = text,
    })
end
