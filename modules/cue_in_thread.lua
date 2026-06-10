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

local https = require("https")
local json  = require("json")

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
-- LLM API call
----------------------------------------------------------------------

--- Call OpenAI chat completions API.
-- Returns response text or nil + error.
local function callOpenAI(transcript, systemPrompt, model, apiKey)
    local url = "https://api.openai.com/v1/chat/completions"

    local body = json.encode({
        model = model,
        messages = {
            { role = "system", content = systemPrompt },
            { role = "user",   content = transcript },
        },
        temperature = 0.3,
    })

    local code, respBody = https.request(url, {
        method  = "POST",
        headers = {
            ["Content-Type"]  = "application/json",
            ["Authorization"] = "Bearer " .. apiKey,
        },
        data = body,
    })

    if code ~= 200 then
        return nil, "OpenAI HTTP " .. tostring(code) .. ": " .. tostring(respBody):sub(1, 300)
    end

    local ok, parsed = pcall(json.decode, respBody)
    if not ok or type(parsed) ~= "table" then
        return nil, "OpenAI: failed to parse response"
    end

    local choices = parsed.choices
    if not choices or not choices[1] then
        return nil, "OpenAI: no choices in response"
    end

    return choices[1].message.content
end

--- Call Anthropic Messages API.
-- Returns response text or nil + error.
local function callAnthropic(transcript, systemPrompt, model, apiKey)
    local url = "https://api.anthropic.com/v1/messages"

    local body = json.encode({
        model      = model,
        max_tokens = 512,
        system     = systemPrompt,
        messages   = {
            { role = "user", content = transcript },
        },
    })

    local code, respBody = https.request(url, {
        method  = "POST",
        headers = {
            ["Content-Type"]      = "application/json",
            ["x-api-key"]         = apiKey,
            ["anthropic-version"] = "2023-06-01",
        },
        data = body,
    })

    if code ~= 200 then
        return nil, "Anthropic HTTP " .. tostring(code) .. ": " .. tostring(respBody):sub(1, 300)
    end

    local ok, parsed = pcall(json.decode, respBody)
    if not ok or type(parsed) ~= "table" then
        return nil, "Anthropic: failed to parse response"
    end

    local content = parsed.content
    if not content or not content[1] then
        return nil, "Anthropic: no content in response"
    end

    return content[1].text
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

while true do
    local req = requestChannel:demand()
    if req == "quit" then break end

    local transcript = req.transcript

    -- 1. Call LLM
    local llmText, llmErr
    if cfg.provider == "anthropic" then
        llmText, llmErr = callAnthropic(transcript, cfg.system_prompt, cfg.model, cfg.anthropic_api_key)
    else
        llmText, llmErr = callOpenAI(transcript, cfg.system_prompt, cfg.model, cfg.openai_api_key)
    end

    if not llmText then
        pushError("LLM call failed: " .. tostring(llmErr))
        -- keep thread alive for next request
    else
        -- 2. Parse the JSON response {"slug": "...", "script": "..."}
        -- Strip any accidental markdown fences the model might add
        local cleaned = llmText:match("```json%s*(.-)%s*```") or
                        llmText:match("```%s*(.-)%s*```") or
                        llmText

        local ok, parsed = pcall(json.decode, cleaned)
        if not ok or type(parsed) ~= "table" or not parsed.slug or not parsed.script then
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
end
