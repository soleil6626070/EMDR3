-- modules/identification.lua
-- Orchestrates the target-identification flow: the ordered step table, current
-- position, write-through checkpointing into assessment.json, the ongoing
-- marker, and resume. Screens read identification.currentStep() for their
-- parameters and call identification.advance() when done.
--
-- Lifecycle: begin() (menu) → ident_prelude → ident_agent → beginTarget()
-- (after post-call extraction; creates the target dir + record + marker) →
-- assessment steps → review confirm calls complete(). Escape anywhere after
-- beginTarget leaves the marker on disk = resumable from the menu. The agent
-- call itself is not resumable: before beginTarget there is no marker and
-- nothing to clean up.

local config          = require("config")
local assessment_json = require("modules.assessment_json")

local identification = {}

local MARKER_FILE = "resources/audio/transcription_queue/.identification_ongoing"
local IDENT_QUEUE = "resources/audio/ident_queue"

-- Current flow state (nil / 0 when no identification is active)
identification.targetDir  = nil   -- absolute path to output_data/targets/<slug>
identification.targetName = nil   -- the slug
identification.started    = nil   -- "YYYY-MM-DD HH:MM:SS"
identification.stepIndex  = 0

----------------------------------------------------------------------
-- Step table
----------------------------------------------------------------------

identification.steps = {
    { id = "image",   screen = "ident_agent", label = "target image" },
    { id = "nc",      screen = "ident_stage", label = "negative cognition",
      stage = "negative_cognition",
      interlude = "resources/audio/ident/interlude_nc",
      question  = "resources/audio/ident/question_nc",
      check_prompt = "prompts/check_negative_cognition.md",
      use_cognition_list = true },
    { id = "pc",      screen = "ident_stage", label = "positive cognition",
      stage = "positive_cognition",
      interlude = "resources/audio/ident/interlude_pc",
      question  = "resources/audio/ident/question_pc",
      check_prompt = "prompts/check_positive_cognition.md",
      use_cognition_list = true },
    { id = "voc",     screen = "ident_voc",   label = "VoC rating" },
    { id = "emotion", screen = "ident_stage", label = "emotions",
      stage = "emotion",
      interlude = "resources/audio/ident/interlude_emotion",
      question  = "resources/audio/ident/question_emotion",
      check_prompt = "prompts/check_emotion.md" },
    { id = "sud",     screen = "ident_sud",   label = "SUD rating" },
    { id = "body",    screen = "ident_stage", label = "body sensations",
      stage = "body",
      interlude = "resources/audio/ident/interlude_body",
      question  = "resources/audio/ident/question_body",
      check_prompt = "prompts/check_body.md" },
    { id = "review",  screen = "ident_review", label = "review" },
}

local stepIndexById = {}
for i, step in ipairs(identification.steps) do stepIndexById[step.id] = i end

----------------------------------------------------------------------
-- Paths / small helpers
----------------------------------------------------------------------

local function src()
    return love.filesystem.getSource()
end

local function markerPath()
    return src() .. "/" .. MARKER_FILE
end

function identification.recordPath()
    return identification.targetDir and (identification.targetDir .. "/assessment.json") or nil
end

function identification.record()
    local path = identification.recordPath()
    return path and assessment_json.load(path) or nil
end

--- Delete leftover answer WAVs. Ident answers are only durable once their
--- check passes (the stage replays its question on resume), so orphans are
--- pure garbage.
local function sweepIdentQueue()
    os.execute('rm -f "' .. src() .. "/" .. IDENT_QUEUE .. '"/*.wav')
end

----------------------------------------------------------------------
-- Flow control
----------------------------------------------------------------------

--- Start a fresh identification (from the menu). No marker yet — the agent
--- call is not resumable.
function identification.begin()
    identification.targetDir  = nil
    identification.targetName = nil
    identification.started    = os.date("%Y-%m-%d %H:%M:%S")
    identification.stepIndex  = 1
    sweepIdentQueue()
    switchScreen("ident_prelude")
end

--- Called once, after the agent call's transcript has been extracted. Creates
--- the target directory (suffixing the slug on collision), the initial
--- assessment record, and the resume marker — from here on the flow is
--- durable. Returns the resolved target dir.
-- @param t { slug, image, confirmed, conversation_id }
function identification.beginTarget(t)
    local base = src() .. "/" .. (config.TARGETS_DIR or "output_data/targets")

    local slug = t.slug
    local dir = base .. "/" .. slug
    local n = 1
    while io.open(dir .. "/assessment.json", "r") or io.open(dir .. "/script.txt", "r") do
        n = n + 1
        slug = t.slug .. "_" .. n
        dir = base .. "/" .. slug
    end

    identification.targetDir  = dir
    identification.targetName = slug

    local path = identification.recordPath()
    assessment_json.ensureDir(path)
    assessment_json.merge(path, {
        version         = 1,
        target          = slug,
        started         = identification.started,
        conversation_id = t.conversation_id,
        image           = { description = t.image, confirmed = t.confirmed or false },
    })
    identification.writeMarker()
    return dir
end

--- Advance to the next step's screen. The step index is derived from the
--- record on resume, so this is safe to call from any step screen.
function identification.advance()
    identification.stepIndex = identification.stepIndex + 1
    local step = identification.steps[identification.stepIndex]
    if step then
        switchScreen(step.screen)
    else
        switchScreen("menu")
    end
end

function identification.currentStep()
    return identification.steps[identification.stepIndex]
end

function identification.isActive()
    return identification.targetDir ~= nil
end

----------------------------------------------------------------------
-- Checkpoints (write-through; every call lands on disk immediately)
----------------------------------------------------------------------

--- Save a completed stage. stageTable: { answer, flagged, attempts, exchanges }.
function identification.setAnswer(stageKey, stageTable)
    assessment_json.setStage(identification.recordPath(), stageKey, stageTable)
end

--- Save a rating ("voc" or "sud").
function identification.setRating(kind, value)
    assessment_json.merge(identification.recordPath(), { [kind] = value })
end

--- Review confirmed: mark completed and clear the marker. The review screen
--- triggers cue-in generation itself.
function identification.complete()
    assessment_json.merge(identification.recordPath(), { completed = true })
    identification.clearMarker()
    identification.reset()
end

--- Explicit discard from the review screen: the record stays on disk for
--- inspection but the flow is no longer resumable.
function identification.discard()
    identification.clearMarker()
    identification.reset()
end

function identification.reset()
    identification.targetDir  = nil
    identification.targetName = nil
    identification.started    = nil
    identification.stepIndex  = 0
end

----------------------------------------------------------------------
-- Marker + resume
----------------------------------------------------------------------

-- Marker file: three lines — targetDir, targetName, started. Deliberately
-- minimal: progress truth lives in assessment.json, so marker and record can
-- never disagree.
function identification.writeMarker()
    local path = markerPath()
    os.execute('mkdir -p "' .. path:match("^(.*)/[^/]+$") .. '"')
    local f = io.open(path, "w")
    if f then
        f:write(table.concat({
            identification.targetDir,
            identification.targetName,
            identification.started,
        }, "\n"))
        f:close()
    end
end

function identification.clearMarker()
    os.remove(markerPath())
end

--- First incomplete step id for a record, in flow order. Ratings count as
--- complete when non-null; stages when they have an answer.
local function nextStepId(record)
    local stages = record.stages or {}
    if not (stages.negative_cognition and stages.negative_cognition.answer) then return "nc" end
    if not (stages.positive_cognition and stages.positive_cognition.answer) then return "pc" end
    if record.voc == nil then return "voc" end
    if not (stages.emotion and stages.emotion.answer) then return "emotion" end
    if record.sud == nil then return "sud" end
    if not (stages.body and stages.body.answer) then return "body" end
    return "review"
end

--- Read the marker and validate it against its record. Returns
--- { targetDir, targetName, started, nextStepId, nextStepLabel } or nil.
function identification.getOngoing()
    local f = io.open(markerPath(), "r")
    if not f then return nil end
    local targetDir  = f:read("*l")
    local targetName = f:read("*l")
    local started    = f:read("*l")
    f:close()

    if not targetDir or targetDir == "" or not targetName or targetName == "" then
        return nil
    end

    local record = assessment_json.load(targetDir .. "/assessment.json")
    if not record or record.completed then return nil end

    local stepId = nextStepId(record)
    return {
        targetDir     = targetDir,
        targetName    = targetName,
        started       = started or "",
        nextStepId    = stepId,
        nextStepLabel = identification.steps[stepIndexById[stepId]].label,
    }
end

--- Restore a paused/crashed identification from getOngoing()'s table and
--- switch straight to the first incomplete step's screen.
function identification.resume(o)
    identification.targetDir  = o.targetDir
    identification.targetName = o.targetName
    identification.started    = o.started
    identification.stepIndex  = stepIndexById[o.nextStepId]
    sweepIdentQueue()
    switchScreen(identification.steps[identification.stepIndex].screen)
end

----------------------------------------------------------------------
-- Rating screen options (consumed by main.lua's screen registry)
----------------------------------------------------------------------

function identification.ratingOpts(kind)
    if kind == "voc" then
        local opts
        opts = {
            min = 1, max = 7, default = 4,
            title_lines  = {},  -- filled on load: includes the positive cognition
            anchor_min   = "1 — completely false",
            anchor_max   = "7 — completely true",
            escape_label = "Escape — pause",
            on_load = function()
                local record = identification.record()
                local pc = record and record.stages.positive_cognition
                           and record.stages.positive_cognition.answer or "your positive belief"
                opts.title_lines = {
                    "Think of the memory, and the words:",
                    '"' .. pc .. '"',
                    "How true do they feel to you now?",
                }
            end,
            on_confirm = function(value)
                identification.setRating("voc", value)
                identification.advance()
            end,
            on_escape = function() switchScreen("menu") end,
        }
        return opts
    end

    -- kind == "sud"
    return {
        min = 0, max = 10, default = 5,
        title_lines  = { "Bring up the picture, and those negative words.",
                         "How disturbing does it feel right now?" },
        anchor_min   = "0 — no disturbance",
        anchor_max   = "10 — worst imaginable",
        escape_label = "Escape — pause",
        on_confirm = function(value)
            identification.setRating("sud", value)
            identification.advance()
        end,
        on_escape = function() switchScreen("menu") end,
    }
end

return identification
