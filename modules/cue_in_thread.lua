-- modules/cue_in_thread.lua
-- Background worker: receives a TII transcript, calls an LLM to generate a
-- cue-in script + slug name, saves files, then generates TTS audio.
-- Runs in an isolated love.thread.

local requestChannel  = love.thread.getChannel("cue_in_request")
local responseChannel = love.thread.getChannel("cue_in_response")
local configChannel   = love.thread.getChannel("cue_in_config")

local cfg = configChannel:demand()

package.cpath = cfg.source_path .. "/lib/?.so;" .. cfg.source_path .. "/lib/?.dll;" .. package.cpath
package.path  = cfg.source_path .. "/lib/?.lua;" .. cfg.source_path .. "/lib/?/init.lua;" .. package.path

local https      = require("https")
local llm_client = require("llm_client")

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function pushError(msg)
    responseChannel:push({ success = false, error = msg })
end

--- Make a directory path recursively (works on Linux/Mac/Windows).
local function mkdirp(path)
    os.execute('mkdir -p "' .. path .. '"')
end

--- Write text to a file, creating parent dirs as needed.
local function writeFile(path, text)
    local f = io.open(path, "w")
    if not f then return false, "cannot open " .. path end
    f:write(text)
    f:close()
    return true
end

----------------------------------------------------------------------
-- TTS via ElevenLabs
----------------------------------------------------------------------

local function generateTTS(scriptText, outPath)
    local url = cfg.elevenlabs_base_url .. "/text-to-speech/" .. cfg.elevenlabs_voice_id

    local escaped = scriptText:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
    local body = string.format(
        '{"text":"%s","model_id":"%s","voice_settings":{"stability":0.5,"similarity_boost":0.75}}',
        escaped, cfg.elevenlabs_model_id
    )

    local code, respBody = https.request(url, {
        method  = "POST",
        headers = {
            ["Accept"]       = "audio/mpeg",
            ["Content-Type"] = "application/json",
            ["xi-api-key"]   = cfg.elevenlabs_api_key,
        },
        data = body,
    })

    if code ~= 200 then
        return false, "ElevenLabs TTS HTTP " .. tostring(code)
    end

    local ok, writeErr = writeFile(outPath, respBody)
    if not ok then
        return false, writeErr
    end

    return true
end

----------------------------------------------------------------------
-- Main loop
----------------------------------------------------------------------

--- v2 path: the target folder already exists (created after extraction); the
--- LLM turns the structured assessment into just the script, then TTS renders
--- the audio. Response contract: {"script": "..."}.
local function generateFromAssessment(req)
    local llmText, llmErr = llm_client.chat({
        provider = cfg.provider,
        model    = cfg.model,
        api_key  = cfg.provider == "anthropic" and cfg.anthropic_api_key or cfg.openai_api_key,
        system   = cfg.assessment_prompt,
        user     = req.assessment,
    })

    if not llmText then
        pushError("LLM call failed: " .. tostring(llmErr))
        return
    end

    local parsed = llm_client.parse_json(llmText)
    if not parsed or type(parsed.script) ~= "string" or parsed.script == "" then
        pushError("LLM returned unexpected format: " .. tostring(llmText):sub(1, 200))
        return
    end

    local targetDir = cfg.targets_dir .. "/" .. req.slug
    mkdirp(targetDir)

    local _, sErr = writeFile(targetDir .. "/script.txt", parsed.script)
    if sErr then
        pushError("Failed to save script: " .. tostring(sErr))
        return
    end

    local ttsOk, ttsErr = generateTTS(parsed.script, targetDir .. "/cue_in.mp3")
    if not ttsOk then
        pushError("TTS failed: " .. tostring(ttsErr))
        return
    end

    responseChannel:push({ success = true, slug = req.slug })
end

while true do
    local req = requestChannel:demand()
    if req == "quit" then break end

    if req.slug then
        generateFromAssessment(req)
        goto continue
    end

    local transcript = req.transcript

    -- 1. Call LLM
    local llmText, llmErr = llm_client.chat({
        provider = cfg.provider,
        model    = cfg.model,
        api_key  = cfg.provider == "anthropic" and cfg.anthropic_api_key or cfg.openai_api_key,
        system   = cfg.system_prompt,
        user     = transcript,
    })

    if not llmText then
        pushError("LLM call failed: " .. tostring(llmErr))
        -- keep thread alive for next request
    else
        -- 2. Parse the JSON response {"slug": "...", "script": "..."}
        local parsed = llm_client.parse_json(llmText)
        if not parsed or not parsed.slug or not parsed.script then
            pushError("LLM returned unexpected format: " .. tostring(llmText):sub(1, 200))
        else
            local slug   = parsed.slug:gsub("[^%w_%-]", "_"):lower()
            local script = parsed.script

            -- 3. Create target directory and save files
            local targetDir = cfg.targets_dir .. "/" .. slug
            mkdirp(targetDir)

            local _, tErr = writeFile(targetDir .. "/transcript.txt", transcript)
            if tErr then print("[CueInThread] Warning: " .. tErr) end

            local _, sErr = writeFile(targetDir .. "/script.txt", script)
            if sErr then
                pushError("Failed to save script: " .. tostring(sErr))
            else
                -- 4. Generate TTS audio
                local ttsOk, ttsErr = generateTTS(script, targetDir .. "/cue_in.mp3")
                if not ttsOk then
                    pushError("TTS failed: " .. tostring(ttsErr))
                else
                    responseChannel:push({ success = true, slug = slug })
                end
            end
        end
    end

    ::continue::
end
