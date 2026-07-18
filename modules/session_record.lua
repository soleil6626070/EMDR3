-- modules/session_record.lua
-- Main-thread API for the per-session JSON record saved under
-- output_data/targets/<slug>/sessions/session_<id>.json.
--
-- The main thread is the single writer of record files: ratings are written
-- here directly (durable the moment the user confirms them), and transcribed
-- responses are written by modules/transcription.lua as worker results arrive.
-- The whisper worker itself never touches these files, so writes cannot race.

local session      = require("modules.session")
local session_json = require("modules.session_json")

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

--- Create the record at session start, once the pre-rating is confirmed.
function session_record.begin(pre_sud)
    local path = session_record.currentPath()
    session_json.ensureDir(path)
    session_json.merge(path, {
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
    session_json.merge(record_path, { post_sud = post_sud, completed = true })
end

return session_record
