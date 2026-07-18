local session = {}

session.currentCycle = 0
session.totalCycles = 0
session.active = false
session.startTimestamp = ""
-- Absolute path to the selected target's directory (set by target_select screen)
session.selectedTargetDir = nil
session.selectedTargetName = nil
-- Last cycle whose response WAV was saved (0 = none yet); resume restarts at +1
session.lastCompletedCycle = 0
-- Set by menu resume; oscillating consumes it to replay confirm + cue-in once
session.resuming = false

local ONGOING_FILE = "resources/audio/transcription_queue/.session_ongoing"

local function ongoingPath()
    return love.filesystem.getSource() .. "/" .. ONGOING_FILE
end

function session.start(totalCycles)
    session.currentCycle = 1
    session.totalCycles = totalCycles
    session.active = true
    session.startTimestamp = os.date("%Y%m%d_%H%M%S")
    session.lastCompletedCycle = 0
    session.resuming = false
    session.writeOngoing()
end

--- Restore a paused/crashed session from a marker table (see getOngoing).
--- The caller decides which screen to enter: oscillating for the next cycle,
--- or post_rating if every cycle already completed.
function session.resume(o)
    session.startTimestamp     = o.timestamp
    session.totalCycles        = o.totalCycles
    session.lastCompletedCycle = o.lastCompleted
    session.currentCycle       = o.lastCompleted + 1
    session.selectedTargetDir  = o.targetDir
    session.selectedTargetName = o.targetName
    session.active   = true
    session.resuming = true
end

function session.nextCycle()
    session.currentCycle = session.currentCycle + 1
    return session.currentCycle <= session.totalCycles
end

function session.isLastCycle()
    return session.currentCycle >= session.totalCycles
end

function session.getResponseFilename()
    return string.format("resources/audio/transcription_queue/response_%s_cycle_%d.wav",
        session.startTimestamp, session.currentCycle)
end

--- Record that the current cycle's response has been saved, and persist the marker.
function session.completeCycle()
    session.lastCompletedCycle = session.currentCycle
    session.writeOngoing()
end

-- Marker file: one value per line — timestamp, lastCompletedCycle, targetDir,
-- targetName, totalCycles. Written at session start (lastCompleted = 0) and
-- after every saved response; cleared only when the post-rating closes the
-- session, so both crashes and Escape-to-menu leave a resumable session.
function session.writeOngoing()
    local path = ongoingPath()
    os.execute('mkdir -p "' .. path:match("^(.*)/[^/]+$") .. '"')
    local f = io.open(path, "w")
    if f then
        f:write(table.concat({
            session.startTimestamp,
            tostring(session.lastCompletedCycle),
            session.selectedTargetDir or "",
            session.selectedTargetName or "",
            tostring(session.totalCycles),
        }, "\n"))
        f:close()
    end
end

function session.clearOngoing()
    os.remove(ongoingPath())
end

--- Read the marker. Returns { timestamp, lastCompleted, targetDir, targetName,
--- totalCycles } or nil if absent or unusable (including old two-line markers,
--- which lack the target and cannot be resumed safely).
function session.getOngoing()
    local f = io.open(ongoingPath(), "r")
    if not f then return nil end
    local timestamp     = f:read("*l")
    local lastCompleted = tonumber(f:read("*l"))
    local targetDir     = f:read("*l")
    local targetName    = f:read("*l")
    local totalCycles   = tonumber(f:read("*l"))
    f:close()

    if not timestamp or timestamp == "" or not lastCompleted
        or not targetDir or targetDir == "" or not totalCycles then
        return nil
    end
    return {
        timestamp     = timestamp,
        lastCompleted = lastCompleted,
        targetDir     = targetDir,
        targetName    = targetName or "",
        totalCycles   = totalCycles,
    }
end

function session.reset()
    session.currentCycle = 0
    session.totalCycles = 0
    session.active = false
    session.startTimestamp = ""
    session.selectedTargetDir  = nil
    session.selectedTargetName = nil
    session.lastCompletedCycle = 0
    session.resuming = false
end

return session
