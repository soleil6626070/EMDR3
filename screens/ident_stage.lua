-- screens/ident_stage.lua
-- One parameterized screen for every spoken assessment stage (negative
-- cognition, positive cognition, emotion, body sensations). Reads its
-- parameters from identification.currentStep().
--
-- Phase machine:
--   interlude → question → recording → thinking → (followup → recording)* →
--   advance (via identification.setAnswer + identification.advance)
--
-- "thinking" covers both the whisper wait and the adequacy-check wait under
-- one visual: a bridge phrase plays, a breathing circle animates, and the
-- background shader speeds up. Escape anywhere = pause (checkpoints + marker
-- stay on disk; the stage replays from its question on resume).

local config         = require("config")
local wav            = require("modules.wav")
local transcription  = require("modules.transcription")
local tts            = require("modules.tts")
local identification = require("modules.identification")
local check          = require("modules.check")

local ident_stage = {}

local IDENT_QUEUE = "resources/audio/ident_queue"
local BRIDGE_DIR  = "resources/audio/ident/bridge"

local step
local phase           -- "interlude" | "question" | "recording" | "thinking" | "followup"
local source          -- currently playing audio source (interlude/question/bridge/followup)
local followupSource  -- TTS follow-up waiting to play after the bridge
local mic
local attempts        -- recordings made this stage (1 question + N follow-ups)
local exchanges       -- { { question, response }, ... }
local currentQuestion -- text of the question the next answer responds to
local lastUsable      -- last non-empty transcript, fallback answer when capped
local transcriptResult -- set by the enqueueRaw callback, consumed in update()
local checkResult      -- set by the check callback, consumed in update()
local screenAlive     -- guards stale async callbacks after Escape/advance
local followupState   -- "waiting" (TTS generating / bridge playing) | "playing"
local followupFailed  -- TTS failed: fall back to on-screen text only

local pulseTimer, breatheTimer, speedMult
local fontQuestion, fontStatus, fontHint
local bgShader, shaderTime, spinTime


----------------------------------------------------------------------
-- Audio helpers
----------------------------------------------------------------------

--- Play a random mp3 from a source-tree directory. Returns the source or nil
--- (missing audio degrades to text-on-screen, never blocks the flow).
local function playFromDir(dir)
    local items = love.filesystem.getDirectoryItems(dir)
    local files = {}
    for _, name in ipairs(items) do
        if name:match("%.mp3$") then files[#files + 1] = dir .. "/" .. name end
    end
    if #files == 0 then return nil end
    local s = love.audio.newSource(files[love.math.random(#files)], "static")
    s:play()
    return s
end

local function stopAudio()
    if source then source:stop(); source = nil end
    if followupSource then followupSource:stop(); followupSource = nil end
end

----------------------------------------------------------------------
-- Phase transitions
----------------------------------------------------------------------

local function startQuestion()
    phase = "question"
    source = playFromDir(step.question)
    -- No cached audio: the question text is on screen; go straight to recording
    if not source then ident_stage._startRecording() end
end

function ident_stage._startRecording()
    phase = "recording"
    pulseTimer = 0
    local devices = love.audio.getRecordingDevices()
    if devices and #devices > 0 then
        mic = devices[1]
        -- ~23s mono buffer at 44100 Hz, 16-bit (same as noticed.lua)
        mic:start(1024 * 1024, 44100, 16, 1)
    else
        mic = nil
    end
end

local function startThinking()
    phase = "thinking"
    breatheTimer = 0
    source = playFromDir(BRIDGE_DIR)
end

--- Save the stage and move on.
local function accept(answer, flagged)
    identification.setAnswer(step.stage, {
        answer    = answer,
        flagged   = flagged,
        attempts  = attempts,
        exchanges = exchanges,
    })
    screenAlive = false
    stopAudio()
    identification.advance()
end

local function acceptCapped(refined)
    accept(refined or lastUsable or "(no answer captured)", true)
end

local function followupsExhausted()
    return (attempts - 1) >= (config.IDENT_MAX_FOLLOWUPS or 3)
end

--- An attempt produced no usable audio/text: replay the question, or give up
--- into the flagged path once the cap is reached.
local function retryQuestion()
    if followupsExhausted() then
        acceptCapped(nil)
    else
        startQuestion()
    end
end

local function stopAndSave()
    local data
    if mic and mic:isRecording() then data = mic:stop() end

    -- No mic at all: don't loop the user through silent retries — accept a
    -- placeholder, flag the stage for the review screen, and move on.
    if not mic then
        attempts = attempts + 1
        acceptCapped(nil)
        return
    end

    attempts = attempts + 1

    if not data or data:getSampleCount() == 0 then
        retryQuestion()
        return
    end

    local root = love.filesystem.getSource()
    os.execute('mkdir -p "' .. root .. "/" .. IDENT_QUEUE .. '"')
    local outPath = string.format("%s/%s/ident_%s_%s_%d.wav",
        root, IDENT_QUEUE, identification.targetName or "unknown", step.id, attempts)

    local f = io.open(outPath, "wb")
    if not f then
        retryQuestion()
        return
    end
    f:write(wav.encode(data))
    f:close()

    startThinking()
    transcription.enqueueRaw(outPath, function(ok, text)
        if screenAlive then transcriptResult = { ok = ok, text = text } end
    end)
end

----------------------------------------------------------------------
-- Async result handling (main thread, consumed from update)
----------------------------------------------------------------------

local function handleTranscript(res)
    if not res.ok or res.text == "" then
        retryQuestion()
        return
    end

    lastUsable = res.text
    exchanges[#exchanges + 1] = { question = currentQuestion, response = res.text }

    check.evaluate(step, exchanges, function(ok, result)
        if not screenAlive then return end
        checkResult = { ok = ok, result = result }
    end)
end

local function handleCheck(res)
    if not res.ok or type(res.result) ~= "table" then
        -- Check unavailable/unparseable: fail soft — retry, or cap out
        retryQuestion()
        return
    end

    local r = res.result
    if r.adequate then
        accept(r.refined_answer or lastUsable, false)
    elseif followupsExhausted() or not r.followup then
        acceptCapped(r.refined_answer)
    else
        -- Ask the follow-up: TTS it now; it plays once the bridge finishes
        currentQuestion = r.followup
        phase = "followup"
        followupState = "waiting"
        followupFailed = false
        tts.speak(r.followup, {}, function(ok, ttsSource)
            if not screenAlive then return end
            if ok then
                followupSource = ttsSource
            else
                followupFailed = true   -- text stays on screen; recording starts anyway
            end
        end)
    end
end

----------------------------------------------------------------------
-- Screen callbacks
----------------------------------------------------------------------

function ident_stage.load()
    step = identification.currentStep()

    phase            = "interlude"
    source           = nil
    followupSource   = nil
    mic              = nil
    attempts         = 0
    exchanges        = {}
    currentQuestion  = step.question_text
    lastUsable       = nil
    transcriptResult = nil
    checkResult      = nil
    screenAlive      = true
    followupState    = nil
    followupFailed   = false

    pulseTimer   = 0
    breatheTimer = 0
    speedMult    = 1.0
    shaderTime   = 0
    spinTime     = 0

    fontQuestion = love.graphics.newFont(28)
    fontStatus   = love.graphics.newFont(18)
    fontHint     = love.graphics.newFont(14)
    bgShader     = love.graphics.newShader("resources/shaders/background.fs")

    source = playFromDir(step.interlude)
    if not source then startQuestion() end
end

function ident_stage.update(dt)
    -- Shader tempo: speeds up while the app is working, eases back otherwise
    local targetMult = (phase == "thinking" or phase == "followup") and 3.0 or 1.0
    speedMult = speedMult + (targetMult - speedMult) * math.min(dt * 2.0, 1.0)
    shaderTime = shaderTime + dt * speedMult
    spinTime   = spinTime + dt * 0.1 * speedMult

    if phase == "interlude" then
        if not source or not source:isPlaying() then startQuestion() end

    elseif phase == "question" then
        if not source or not source:isPlaying() then ident_stage._startRecording() end

    elseif phase == "recording" then
        pulseTimer = pulseTimer + dt

    elseif phase == "thinking" or phase == "followup" then
        breatheTimer = breatheTimer + dt

        -- Consume async results
        if transcriptResult then
            local res = transcriptResult
            transcriptResult = nil
            handleTranscript(res)
        end
        if checkResult then
            local res = checkResult
            checkResult = nil
            handleCheck(res)
        end

        -- Followup phase: bridge finishes → play the TTS'd follow-up → record.
        -- While the TTS is still generating, the breathing circle holds the gap.
        if phase == "followup" then
            if followupState == "waiting" then
                local bridgeDone = not (source and source:isPlaying())
                if bridgeDone then
                    if followupSource then
                        source = followupSource
                        followupSource = nil
                        source:play()
                        followupState = "playing"
                    elseif followupFailed then
                        ident_stage._startRecording()
                    end
                end
            elseif followupState == "playing" then
                if not (source and source:isPlaying()) then
                    ident_stage._startRecording()
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

local colour1 = {0.15, 0.35, 0.55, 1.0}
local colour2 = {0.05, 0.20, 0.40, 1.0}
local colour3 = {0.25, 0.50, 0.65, 1.0}

local function drawBackground(W, H)
    bgShader:send("time", shaderTime)
    bgShader:send("spin_time", spinTime)
    bgShader:send("colour_1", colour1)
    bgShader:send("colour_2", colour2)
    bgShader:send("colour_3", colour3)
    bgShader:send("contrast", 1.0)
    bgShader:send("spin_amount", 0.0)
    love.graphics.setShader(bgShader)
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
    love.graphics.setShader()
end

local function drawBreathingCircle(W, H)
    -- Continuous breath: in over breathe_in_duration, out over breathe_out_duration
    local inDur  = config.breathe_in_duration or 4.0
    local outDur = config.breathe_out_duration or 4.0
    local t = breatheTimer % (inDur + outDur)
    local eased
    if t < inDur then
        eased = 0.5 - 0.5 * math.cos((t / inDur) * math.pi)
    else
        eased = 0.5 + 0.5 * math.cos(((t - inDur) / outDur) * math.pi)
    end
    local rMin, rMax = 24, (config.breathe_max_radius or 96) * 0.8
    local radius = rMin + (rMax - rMin) * eased

    love.graphics.setColor(0.85, 0.90, 1.0, 0.35)
    love.graphics.circle("fill", W / 2, H * 0.62, radius)
    love.graphics.setColor(0.85, 0.90, 1.0, 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", W / 2, H * 0.62, radius)
end

function ident_stage.draw()
    local W = love.graphics.getWidth()
    local H = love.graphics.getHeight()

    drawBackground(W, H)

    -- Question text (current question — follow-ups replace it)
    love.graphics.setFont(fontQuestion)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(currentQuestion or "", W * 0.15, H * 0.2, W * 0.7, "center")

    if phase == "recording" then
        if mic then
            local pulse = 0.5 + 0.5 * math.sin(pulseTimer * 4)
            love.graphics.setColor(0.9, 0.1, 0.1, pulse)
            love.graphics.circle("fill", W / 2 - 80, H * 0.62, 10)
            love.graphics.setFont(fontStatus)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("Recording...", W / 2 - 60, H * 0.62 - fontStatus:getHeight() / 2)
        else
            love.graphics.setFont(fontStatus)
            love.graphics.setColor(1.0, 0.75, 0.35)
            local warn = "No microphone detected — check your input device"
            love.graphics.print(warn, (W - fontStatus:getWidth(warn)) / 2, H * 0.62)
        end
    elseif phase == "thinking" or phase == "followup" then
        drawBreathingCircle(W, H)
    end

    -- Hints
    love.graphics.setFont(fontHint)
    love.graphics.setColor(0.75, 0.82, 0.95, 0.8)
    local hint
    if phase == "recording" then
        hint = mic and "Space/Enter — done speaking   Escape — pause"
                    or "Space/Enter — skip   Escape — pause"
    elseif phase == "interlude" or phase == "question" then
        hint = "Space/Enter — skip audio   Escape — pause"
    else
        hint = "Escape — pause"
    end
    love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
end

function ident_stage.keypressed(k)
    if k == "escape" then
        screenAlive = false
        stopAudio()
        if mic and mic:isRecording() then mic:stop() end
        switchScreen("menu")   -- marker stays on disk: resumable
        return
    end

    if k == "space" or k == "return" or k == "kpenter" then
        if phase == "recording" then
            stopAndSave()
        elseif phase == "interlude" then
            if source then source:stop() end
            startQuestion()
        elseif phase == "question" then
            if source then source:stop() end
            ident_stage._startRecording()
        end
    end
end

return ident_stage
