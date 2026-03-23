-- modules/transcription_thread.lua
-- Worker thread: receives WAV file paths, runs whisper-cli, writes results
-- directly to the output file, deletes the WAV, and pushes a status notification.
-- Runs in an isolated love.thread — no access to love.graphics, love.audio, etc.

local requestChannel = love.thread.getChannel("transcription_request")
local statusChannel  = love.thread.getChannel("transcription_status")
local configChannel  = love.thread.getChannel("transcription_config")

-- Receive config: { whisper_bin, whisper_model, source_path, output_dir }
local cfg = configChannel:demand()
local whisperBin   = cfg.whisper_bin
local whisperModel = cfg.whisper_model
local outputDir    = cfg.output_dir

--- Parse an existing output file into a table of {cycle, text} entries.
local function readExistingResponses(filepath)
    local responses = {}
    local f = io.open(filepath, "r")
    if not f then return responses end

    local content = f:read("*a")
    f:close()

    -- Parse "Response N: text" blocks separated by "---"
    for cycle, text in content:gmatch("Response (%d+): ([^\n]+)") do
        table.insert(responses, { cycle = tonumber(cycle), text = text })
    end

    return responses
end

--- Write all responses (sorted by cycle) to the output file.
local function writeOutputFile(filepath, session_id, responses)
    -- Sort by cycle number
    table.sort(responses, function(a, b) return a.cycle < b.cycle end)

    local f = io.open(filepath, "w")
    if not f then
        print("[TranscriptionThread] Could not open for writing: " .. filepath)
        return false
    end

    f:write("Session: " .. session_id .. "\n")
    for _, resp in ipairs(responses) do
        f:write("\n---\n\nResponse " .. resp.cycle .. ": " .. resp.text .. "\n")
    end

    f:close()
    return true
end

while true do
    local req = requestChannel:demand()

    -- Sentinel value to shut down the thread
    if req == "quit" then break end

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
        -- Read existing output file, insert new response, rewrite
        local outPath = outputDir .. "/session_" .. session_id .. ".txt"
        local responses = readExistingResponses(outPath)

        -- Replace existing entry for this cycle if present (idempotent on retry)
        local found = false
        for i, resp in ipairs(responses) do
            if resp.cycle == cycle then
                responses[i].text = text
                found = true
                break
            end
        end
        if not found then
            table.insert(responses, { cycle = cycle, text = text })
        end

        writeOutputFile(outPath, session_id, responses)

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
