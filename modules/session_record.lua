-- modules/session_record.lua
-- Main-thread API for the per-session JSON record saved under
-- output_data/targets/<slug>/sessions/session_<id>.json.
--
-- The transcription worker is the single writer of these files (it inserts
-- transcribed responses as they complete), so rating writes are routed
-- through its request channel to keep all writes serialized. If the worker
-- is disabled (no whisper), there is no second writer and we write directly.

local session       = require("modules.session")
local transcription = require("modules.transcription")
local session_json  = require("modules.session_json")

local session_record = {}

--- Absolute path of the current session's record file.
function session_record.currentPath()
    local base
    if session.selectedTargetDir then
        base = session.selectedTargetDir .. "/sessions"
    else
        base = love.filesystem.getSource() .. "/output_data"
    end
    return base .. "/session_" .. session.startTimestamp .. ".json"
end

local function write(path, fields)
    if transcription.isEnabled() then
        transcription.pushControl({
            type        = "merge_record",
            record_path = path,
            fields      = fields,
        })
    else
        session_json.merge(path, fields)
    end
end

--- Create the record at session start, once the pre-rating is confirmed.
function session_record.begin(pre_sud)
    write(session_record.currentPath(), {
        session_id   = session.startTimestamp,
        target       = session.selectedTargetName,
        started      = os.date("%Y-%m-%d %H:%M:%S"),
        total_cycles = session.totalCycles,
        pre_sud      = pre_sud,
        completed    = false,
    })
end

--- Close out the record with the post-rating. Takes an explicit path because
--- the session state is reset right after this call.
function session_record.finish(record_path, post_sud)
    write(record_path, { post_sud = post_sud, completed = true })
end

return session_record
