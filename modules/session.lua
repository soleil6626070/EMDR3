local session = {}

session.currentCycle = 0
session.totalCycles = 0
session.active = false
session.startTimestamp = ""

function session.start(totalCycles)
    session.currentCycle = 1
    session.totalCycles = totalCycles
    session.active = true
    session.startTimestamp = os.date("%Y%m%d_%H%M%S")
end

function session.nextCycle()
    session.currentCycle = session.currentCycle + 1
    return session.currentCycle <= session.totalCycles
end

function session.isLastCycle()
    return session.currentCycle >= session.totalCycles
end

function session.getResponseFilename()
    return string.format("resources/audio/user_responses/response_%s_cycle_%d.wav",
        session.startTimestamp, session.currentCycle)
end

function session.reset()
    session.currentCycle = 0
    session.totalCycles = 0
    session.active = false
    session.startTimestamp = ""
end

return session
