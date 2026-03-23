-- modules/transcription.lua
-- Main-thread transcription API. Mirrors tts.lua pattern.

local TranscriptList = require("modules.transcript_list")

local transcription = {}

local thread
local requestChannel
local responseChannel
local configChannel
local config

local nextId = 1
local pending = {}        -- request_id -> { file_path, cycle }
local pendingCount = 0
local results             -- TranscriptList
local wasIdle = true      -- tracks idle transition for auto-save
local sessionTimestamp     -- set by the caller or captured from session

function transcription.init(cfg)
    config = cfg
    results = TranscriptList.new()

    -- Verify whisper-cli and model exist
    local sourcePath = love.filesystem.getSource()
    local binPath   = sourcePath .. "/" .. config.WHISPER_BIN
    local modelPath = sourcePath .. "/" .. config.WHISPER_MODEL

    local binFile = io.open(binPath, "r")
    if not binFile then
        print("[Transcription] WARNING: whisper-cli not found at " .. binPath)
        print("[Transcription] Transcription will be disabled. Run scripts/setup_whisper.sh to install.")
        return
    end
    binFile:close()

    local modelFile = io.open(modelPath, "r")
    if not modelFile then
        print("[Transcription] WARNING: whisper model not found at " .. modelPath)
        print("[Transcription] Transcription will be disabled. Run scripts/setup_whisper.sh to install.")
        return
    end
    modelFile:close()

    requestChannel  = love.thread.getChannel("transcription_request")
    responseChannel = love.thread.getChannel("transcription_response")
    configChannel   = love.thread.getChannel("transcription_config")

    thread = love.thread.newThread("modules/transcription_thread.lua")
    configChannel:push({
        whisper_bin   = binPath,
        whisper_model = modelPath,
        source_path   = sourcePath,
    })
    thread:start()
    print("[Transcription] Worker thread started")
end

--- Queue a WAV file for transcription.
function transcription.enqueue(file_path, cycle)
    if not thread then return end

    local id = nextId
    nextId = nextId + 1

    pending[id] = { file_path = file_path, cycle = cycle }
    pendingCount = pendingCount + 1

    requestChannel:push({
        request_id = id,
        file_path  = file_path,
        cycle      = cycle,
    })

    print(string.format("[Transcription] Enqueued cycle %d: %s (id=%d)", cycle, file_path, id))
end

--- Set the session timestamp for auto-save filename.
function transcription.setSessionTimestamp(timestamp)
    sessionTimestamp = timestamp
end

--- Poll responses from worker thread. Call every frame from love.update().
function transcription.update()
    if not thread then return end

    -- Check for thread errors
    local err = thread:getError()
    if err then
        print("[Transcription] Thread error: " .. err)
    end

    -- Pop all available responses
    while true do
        local resp = responseChannel:pop()
        if not resp then break end

        local info = pending[resp.request_id]
        pending[resp.request_id] = nil
        pendingCount = pendingCount - 1

        if resp.success then
            results:insert(resp.cycle, resp.text)
            -- Delete the WAV file after successful transcription
            local removed = os.remove(resp.file_path)
            if removed then
                print(string.format("[Transcription] Cycle %d done, WAV deleted: %s", resp.cycle, resp.file_path))
            else
                print(string.format("[Transcription] Cycle %d done, WAV delete failed: %s", resp.cycle, resp.file_path))
            end
        else
            -- Preserve WAV on failure for retry
            print(string.format("[Transcription] Cycle %d FAILED (%s), WAV preserved: %s",
                resp.cycle, resp.error or "unknown", resp.file_path))
        end
    end

    -- Auto-save when transitioning from busy to idle
    local isIdle = (pendingCount == 0)
    if isIdle and not wasIdle and results.length > 0 then
        transcription.saveResults(sessionTimestamp or "unknown")
        results = TranscriptList.new()
        print("[Transcription] Session results saved and cleared")
    end
    wasIdle = isIdle
end

--- Return the transcript linked list.
function transcription.getResults()
    return results
end

--- Number of files still queued or being transcribed.
function transcription.getPendingCount()
    return pendingCount
end

--- Total results received so far (for progress display).
function transcription.getCompletedCount()
    return results and results.length or 0
end

--- True when no pending work remains.
function transcription.isIdle()
    return pendingCount == 0
end

--- Serialize linked list to output file.
function transcription.saveResults(timestamp)
    local sourcePath = love.filesystem.getSource()
    local outDir = sourcePath .. "/resources/output_data"
    os.execute('mkdir -p "' .. outDir .. '"')

    local outPath = outDir .. "/session_" .. (timestamp or "unknown") .. ".txt"
    local ok = results:save(outPath, timestamp)
    if ok then
        print("[Transcription] Results saved to " .. outPath)
    else
        print("[Transcription] Failed to save results to " .. outPath)
    end
end

--- Shut down the worker thread.
function transcription.shutdown()
    if thread and thread:isRunning() then
        requestChannel:push("quit")
        thread:wait()
        print("[Transcription] Worker thread stopped")
    end
end

return transcription
