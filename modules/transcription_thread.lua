-- modules/transcription_thread.lua
-- Worker thread: receives WAV file paths, runs whisper-cli, returns transcribed text.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local requestChannel  = love.thread.getChannel("transcription_request")
local responseChannel = love.thread.getChannel("transcription_response")
local configChannel   = love.thread.getChannel("transcription_config")

-- Receive config: { whisper_bin, whisper_model, source_path }
local cfg = configChannel:demand()
local whisperBin   = cfg.whisper_bin
local whisperModel = cfg.whisper_model

while true do
    local req = requestChannel:demand()

    -- Sentinel value to shut down the thread
    if req == "quit" then break end

    local request_id = req.request_id
    local file_path  = req.file_path
    local cycle      = req.cycle

    -- Temp output path (whisper appends .txt)
    local tmpBase = os.tmpname()
    -- os.tmpname creates the file on some systems; remove it
    os.remove(tmpBase)

    local cmd = string.format(
        '"%s" -m "%s" -f "%s" --no-timestamps -l en -otxt -of "%s" 2>/dev/null',
        whisperBin, whisperModel, file_path, tmpBase
    )

    local exitCode = os.execute(cmd)
    local txtPath = tmpBase .. ".txt"

    -- In LuaJIT/Lua 5.1, os.execute returns the exit status as a number (0 = success)
    if exitCode == 0 then
        local f = io.open(txtPath, "r")
        if f then
            local text = f:read("*a")
            f:close()
            os.remove(txtPath)

            -- Trim whitespace
            text = text:match("^%s*(.-)%s*$") or ""

            responseChannel:push({
                request_id = request_id,
                cycle      = cycle,
                success    = true,
                text       = text,
                file_path  = file_path,
            })
        else
            os.remove(txtPath)
            responseChannel:push({
                request_id = request_id,
                cycle      = cycle,
                success    = false,
                text       = "",
                file_path  = file_path,
                error      = "Failed to read whisper output file",
            })
        end
    else
        os.remove(txtPath)
        responseChannel:push({
            request_id = request_id,
            cycle      = cycle,
            success    = false,
            text       = "",
            file_path  = file_path,
            error      = "whisper-cli exited with error",
        })
    end
end
