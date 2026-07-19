-- modules/cue_in.lua
-- Main-thread API for cue-in script generation.
-- Calls an LLM to turn a TII transcript into a cue-in script, then uses TTS
-- to produce an audio file. Both steps run on a background thread.
--
-- Usage:
--   cue_in.init(config)
--   cue_in.generate(transcriptText)   -- fire and forget; runs in background
--   cue_in.update()                   -- call every frame from love.update(dt)
--   cue_in.getStatus()                -- "idle"|"generating"|"done"|"error"
--   cue_in.getLastTarget()            -- slug name of the last generated target
--   cue_in.getError()
--   cue_in.shutdown()

local cue_in = {}

local thread
local requestChannel
local responseChannel
local configChannel

local config
local status    = "idle"
local lastTarget = nil
local errorMsg  = nil
local assessmentPromptMissing = false

-- The system prompt that instructs the LLM how to produce the cue-in script.
-- Follows Shapiro's Phase 4 protocol: image → NC (verbatim) → body sensation.
-- Also asks for a short slug name for the target folder.
-- EDIT THIS PROMPT to tune the output.
local SYSTEM_PROMPT = [[
You are an assistant helping an EMDR therapist prepare session materials.

You will receive a transcript of a Target Identification conversation between a therapist-agent and a client. Your job is to produce two things:

1. A SHORT SLUG NAME for this target (2-4 words, lowercase, underscores only, e.g. "pram_incident" or "car_crash_2019"). This will be used as a folder name.

2. A CUE-IN SCRIPT following Shapiro's EMDR protocol for Phase 4 (Desensitization). The cue-in script brings the client back to their target image at the start of a processing session. It must:
   - Be 1-3 sentences maximum
   - Use a gentle, present-tense, directive tone
   - Include exactly three elements in this order: (a) the specific target image/picture the client described, (b) the negative cognition verbatim in the client's own words, (c) the body location where the client feels the disturbance
   - NOT include the positive cognition, VOC rating, emotions list, or SUD rating — those are context for you but do not appear in the spoken script
   - Quote the negative cognition exactly as the client stated it

Respond with ONLY a JSON object in this exact format (no markdown, no explanation):
{"slug": "short_name_here", "script": "The cue-in script text here."}
]]

function cue_in.init(cfg)
    config = cfg

    local assessmentPrompt = love.filesystem.read("prompts/cue_in.md")
    if not assessmentPrompt then
        assessmentPromptMissing = true
        print("[CueIn] WARNING: prompts/cue_in.md not found — assessment-based generation will fail")
    end

    requestChannel  = love.thread.getChannel("cue_in_request")
    responseChannel = love.thread.getChannel("cue_in_response")
    configChannel   = love.thread.getChannel("cue_in_config")

    thread = love.thread.newThread("modules/cue_in_thread.lua")
    configChannel:push({
        source_path       = love.filesystem.getSource(),
        provider          = config.LLM_PROVIDER or "openai",
        model             = config.LLM_MODEL or "gpt-4o-mini",
        openai_api_key    = config.OPENAI_API_KEY or "",
        anthropic_api_key = config.ANTHROPIC_API_KEY or "",
        elevenlabs_api_key = config.ELEVENLABS_API_KEY or "",
        elevenlabs_voice_id = config.ELEVENLABS_VOICE_ID or "",
        elevenlabs_base_url = config.ELEVENLABS_BASE_URL or "https://api.elevenlabs.io/v1",
        elevenlabs_model_id = config.ELEVENLABS_MODEL_ID or "eleven_multilingual_v2",
        targets_dir       = love.filesystem.getSource() .. "/" .. (config.TARGETS_DIR or "output_data/targets"),
        system_prompt     = SYSTEM_PROMPT,
        -- v2 path: script generation from a structured assessment record; the
        -- prompt is editable prose in prompts/cue_in.md
        assessment_prompt = assessmentPrompt or "",
    })
    thread:start()
end

--- Begin generating a cue-in script.
-- @param arg  Either the full text of a TII transcript (legacy path), or a
--             table { slug = <existing target slug>, assessment = <the
--             assessment.json content as text> } — generates script + audio
--             into the already-existing target folder.
function cue_in.generate(arg)
    if status == "generating" then
        print("[CueIn] Already generating, ignoring request")
        return
    end
    if type(arg) == "table" and assessmentPromptMissing then
        status   = "error"
        errorMsg = "prompts/cue_in.md is missing — cannot generate from assessment"
        print("[CueIn] " .. errorMsg)
        return
    end
    status    = "generating"
    errorMsg  = nil
    lastTarget = nil
    if type(arg) == "table" then
        requestChannel:push({ slug = arg.slug, assessment = arg.assessment })
    else
        requestChannel:push({ transcript = arg })
    end
end

--- Call every frame from love.update(dt).
function cue_in.update()
    if not thread then return end

    local err = thread:getError()
    if err then
        print("[CueIn] Thread error: " .. err)
        status   = "error"
        errorMsg = err
        return
    end

    local resp = responseChannel:pop()
    if resp then
        if resp.success then
            status     = "done"
            lastTarget = resp.slug
            print("[CueIn] Done — target: " .. tostring(resp.slug))
        else
            status   = "error"
            errorMsg = resp.error
            print("[CueIn] Error: " .. tostring(resp.error))
        end
    end
end

function cue_in.getStatus()  return status     end
function cue_in.getLastTarget() return lastTarget end
function cue_in.getError()   return errorMsg   end

--- Reset to idle (e.g. after handling the result).
function cue_in.reset()
    status    = "idle"
    errorMsg  = nil
    lastTarget = nil
end

function cue_in.shutdown()
    if thread and thread:isRunning() then
        requestChannel:push("quit")
        thread:wait()
    end
end

return cue_in
