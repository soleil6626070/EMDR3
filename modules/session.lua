local session = {}

session.currentCycle = 0
session.totalCycles = 0
session.active = false
session.startTimestamp = ""
-- Absolute path to the selected target's directory (set by target_select screen)
session.selectedTargetDir = nil
session.selectedTargetName = nil

local ONGOING_FILE = "resources/audio/transcription_queue/.session_ongoing"

function session.start(totalCycles)
    session.currentCycle = 1
    session.totalCycles = totalCycles
    session.active = true
    session.startTimestamp = os.date("%Y%m%d_%H%M%S")
    session.writeOngoing()
end

function session.resume(totalCycles, timestamp, lastCycle)
    session.totalCycles = totalCycles
    session.active = true
    session.startTimestamp = timestamp
    session.currentCycle = lastCycle + 1
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

function session.writeOngoing()
    local path = love.filesystem.getSource() .. "/" .. ONGOING_FILE
    local f = io.open(path, "w")
    if f then
        f:write(session.startTimestamp .. "\n" .. session.currentCycle)
        f:close()
    end
end

function session.clearOngoing()
    os.remove(love.filesystem.getSource() .. "/" .. ONGOING_FILE)
end

function session.getOngoing()
    local path = love.filesystem.getSource() .. "/" .. ONGOING_FILE
    local f = io.open(path, "r")
    if not f then return nil end
    local timestamp = f:read("*l")
    local cycle = tonumber(f:read("*l")) or 0
    f:close()
    return timestamp, cycle
end

function session.reset()
    session.currentCycle = 0
    session.totalCycles = 0
    session.active = false
    session.startTimestamp = ""
    session.selectedTargetDir  = nil
    session.selectedTargetName = nil
end

return session
