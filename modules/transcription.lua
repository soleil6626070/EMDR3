-- modules/transcription.lua
-- Main-thread transcription API. Enqueues WAV files for background whisper-cli
-- processing; the worker returns plain text over the status channel and this
-- module saves it into the session JSON record and deletes the WAV. The main
-- thread is the single writer of record files (ratings are written directly by
-- modules/session_record.lua), so writes can never race.

local session_json = require("modules.session_json")

local transcription = {}

local thread
local requestChannel
local statusChannel
local configChannel

local pendingCount = 0
local completedCount = 0
local enabled = false
local queueDir
local outputDir

-- Raw jobs (identification answers, etc.): transcribe a WAV and hand the text
-- to a callback instead of a session record. Keyed by job_id, like tts.lua.
local rawCallbacks = {}
local nextJobId = 0

--- Parse a queue filename into session_id and cycle number.
-- Expected format: response_{timestamp}_cycle_{N}.wav
local function parseFilename(filename)
    local session_id, cycle = filename:match("^response_(%d+_%d+)_cycle_(%d+)%.wav$")
    if session_id and cycle then
        return session_id, tonumber(cycle)
    end
    return nil, nil
end

--- Locate an existing session record for a recovered WAV by searching every
--- target's sessions/ folder. Returns nil if none exists yet (the worker then
--- falls back to a flat output_data/ record).
local function findRecordPath(targetsBase, session_id)
    local handle = io.popen('ls -1 "' .. targetsBase .. '"/*/sessions/session_'
        .. session_id .. '.json 2>/dev/null | head -1')
    if not handle then return nil end
    local path = handle:read("*l")
    handle:close()
    if path and path ~= "" then return path end
    return nil
end

function transcription.init(cfg)
    local sourcePath = love.filesystem.getSource()
    local whisperBin   = sourcePath .. "/" .. cfg.WHISPER_BIN
    local whisperModel = sourcePath .. "/" .. cfg.WHISPER_MODEL

    -- Validate whisper-cli and model exist
    local binFile = io.open(whisperBin, "r")
    if not binFile then
        print("[Transcription] whisper-cli not found at " .. whisperBin .. " — transcription disabled")
        return
    end
    binFile:close()

    local modelFile = io.open(whisperModel, "r")
    if not modelFile then
        print("[Transcription] Whisper model not found at " .. whisperModel .. " — transcription disabled")
        return
    end
    modelFile:close()

    -- Ensure directories exist
    queueDir = sourcePath .. "/resources/audio/transcription_queue"
    outputDir = sourcePath .. "/output_data"
    os.execute('mkdir -p "' .. queueDir .. '"')
    os.execute('mkdir -p "' .. outputDir .. '"')
    -- Separate queue for raw jobs: kept out of transcription_queue/ so the
    -- session crash-recovery scan below never misreads their filenames.
    os.execute('mkdir -p "' .. sourcePath .. '/resources/audio/ident_queue"')

    enabled = true

    -- Set up channels and start worker thread
    requestChannel = love.thread.getChannel("transcription_request")
    statusChannel  = love.thread.getChannel("transcription_status")
    configChannel  = love.thread.getChannel("transcription_config")

    thread = love.thread.newThread("modules/transcription_thread.lua")
    configChannel:push({
        whisper_bin   = whisperBin,
        whisper_model = whisperModel,
        source_path   = sourcePath,
        output_dir    = outputDir,
    })
    thread:start()

    -- Crash recovery: scan queue dir for leftover .wav files
    local items = love.filesystem.getDirectoryItems("resources/audio/transcription_queue")
    local leftover = {}
    for _, name in ipairs(items) do
        local session_id, cycle = parseFilename(name)
        if session_id and cycle then
            table.insert(leftover, {
                name = name,
                session_id = session_id,
                cycle = cycle,
            })
        end
    end

    -- Sort by session then cycle for ordered processing
    table.sort(leftover, function(a, b)
        if a.session_id == b.session_id then
            return a.cycle < b.cycle
        end
        return a.session_id < b.session_id
    end)

    local targetsBase = sourcePath .. "/" .. (cfg.TARGETS_DIR or "output_data/targets")
    for _, item in ipairs(leftover) do
        local filePath = queueDir .. "/" .. item.name
        transcription.enqueue(filePath, item.cycle, item.session_id,
            findRecordPath(targetsBase, item.session_id))
    end
end

function transcription.enqueue(file_path, cycle, session_id, record_path)
    if not enabled then return end
    pendingCount = pendingCount + 1
    requestChannel:push({
        type        = "transcribe",
        file_path   = file_path,
        cycle       = cycle,
        session_id  = session_id,
        record_path = record_path,
    })
end

--- Transcribe a WAV outside any session record. The callback receives
--- (success, text); on success the WAV is deleted, on failure it is preserved.
-- @param file_path absolute path to a WAV (use resources/audio/ident_queue/)
-- @param callback  function(success, text_or_nil)
function transcription.enqueueRaw(file_path, callback)
    if not enabled then
        print("[Transcription] disabled — cannot transcribe " .. tostring(file_path))
        if callback then callback(false, nil) end
        return
    end
    nextJobId = nextJobId + 1
    rawCallbacks[nextJobId] = callback
    pendingCount = pendingCount + 1
    requestChannel:push({
        type      = "transcribe_raw",
        file_path = file_path,
        job_id    = nextJobId,
    })
end

--- Handle one worker result on the main thread: save the transcript into the
--- session record, then delete the WAV. Deleting only after a successful save
--- keeps responses crash-safe; a failed job preserves its WAV for retry.
local function handleResult(status)
    -- Raw job: hand the text to its callback; no record involved. Empty text is
    -- a successful transcription (the caller decides what silence means).
    if status.job_id then
        local cb = rawCallbacks[status.job_id]
        rawCallbacks[status.job_id] = nil
        if status.success then
            os.remove(status.file_path)
            if cb then cb(true, status.text or "") end
        else
            print("[Transcription] Raw job failed for " .. tostring(status.file_path))
            if cb then cb(false, nil) end
        end
        return
    end

    if status.success and status.text and status.text ~= "" then
        local recordPath = status.record_path
        if not recordPath then
            -- Recovered WAV with no known record (predates per-target records)
            recordPath = outputDir .. "/session_" .. status.session_id .. ".json"
            session_json.ensureDir(recordPath)
        end
        session_json.upsertResponse(recordPath, status.session_id, status.cycle, status.text)
        os.remove(status.file_path)
    else
        print("[Transcription] Failed for " .. tostring(status.file_path)
            .. " — preserving WAV for retry")
    end
end

function transcription.update()
    if not enabled then return end

    -- Check for thread errors
    local err = thread:getError()
    if err then
        print("[Transcription] Thread error: " .. err)
    end

    -- Pop all available worker results
    while true do
        local status = statusChannel:pop()
        if not status then break end
        handleResult(status)
        pendingCount = pendingCount - 1
        completedCount = completedCount + 1
    end
end

function transcription.isIdle()
    return pendingCount == 0
end

function transcription.getPendingCount()
    return pendingCount
end

function transcription.getCompletedCount()
    return completedCount
end

function transcription.shutdown()
    if thread and thread:isRunning() then
        requestChannel:push("quit")
        thread:wait()
    end
    -- Drain and save any final worker results
    if statusChannel then
        while true do
            local status = statusChannel:pop()
            if not status then break end
            handleResult(status)
            pendingCount = pendingCount - 1
            completedCount = completedCount + 1
        end
    end
end

return transcription
