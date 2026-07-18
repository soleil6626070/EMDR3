-- scripts/audio_generation/main.lua
-- Generates all pre-cached TTS audio via the ElevenLabs API, driven by
-- manifest.lua in this directory. Run from project root:
--   love scripts/audio_generation
--
-- Files that already exist are skipped, so re-running after adding a manifest
-- entry only generates the new audio. Delete a file (or set FORCE = true) to
-- regenerate it after editing its text.

local FORCE = false

function love.load()
    -- Project root = the directory love was launched from
    local projectRoot = love.filesystem.getWorkingDirectory()

    -- Load native HTTPS module
    package.cpath = projectRoot .. "/lib/?.so;"
                 .. projectRoot .. "/lib/?.dll;"
                 .. package.cpath
    local https = require("https")

    local manifest = dofile(projectRoot .. "/scripts/audio_generation/manifest.lua")

    -- Parse .env
    local env = {}
    local envFile = io.open(projectRoot .. "/.env", "r")
    if envFile then
        for line in envFile:lines() do
            if not line:match("^%s*#") and line:match("=") then
                local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
                if key then env[key] = value end
            end
        end
        envFile:close()
    else
        print("ERROR: Could not open .env at " .. projectRoot .. "/.env")
        love.event.quit(1)
        return
    end

    local api_key = env.ELEVENLABS_API_EMDR_KEY
    if not api_key then
        print("ERROR: ELEVENLABS_API_EMDR_KEY not found in .env")
        love.event.quit(1)
        return
    end

    -- One voice everywhere: the app voice (Addison 2.0, config.ELEVENLABS_VOICE_ID).
    -- Overridable via ELEVENLABS_VOICE_ID in .env; keep the default in sync with
    -- config.lua.
    local voice_id = env.ELEVENLABS_VOICE_ID or "eR40ATw9ArzDf9h3v7t7"
    local model_id = "eleven_multilingual_v2"
    local base_url = "https://api.elevenlabs.io/v1"

    local generated, skipped, failed = 0, 0, 0

    for _, entry in ipairs(manifest) do
        local outDir = projectRoot .. "/resources/audio/" .. entry.subfolder
        os.execute('mkdir -p "' .. outDir .. '"')

        local escaped_text = entry.text:gsub('\\', '\\\\'):gsub('"', '\\"')
                                       :gsub('\n', '\\n'):gsub('\r', '\\r')
        local body = string.format(
            '{"text":"%s","model_id":"%s","voice_settings":{"stability":0.5,"similarity_boost":0.75,"speed":%.2f}}',
            escaped_text, model_id, entry.speed or 1.0
        )

        for n = 1, entry.variants or 1 do
            local filename = entry.prefix .. "_" .. n .. ".mp3"
            local outPath = outDir .. "/" .. filename

            local existing = io.open(outPath, "rb")
            if existing and not FORCE then
                existing:close()
                skipped = skipped + 1
                print("SKIP (exists): " .. entry.subfolder .. "/" .. filename)
            else
                if existing then existing:close() end
                print(string.format("Generating %s/%s ...", entry.subfolder, filename))

                local code, responseBody = https.request(base_url .. "/text-to-speech/" .. voice_id, {
                    method  = "POST",
                    headers = {
                        ["Accept"]       = "audio/mpeg",
                        ["Content-Type"] = "application/json",
                        ["xi-api-key"]   = api_key,
                    },
                    data = body,
                })

                if code == 200 then
                    local f = io.open(outPath, "wb")
                    if f then
                        f:write(responseBody)
                        f:close()
                        generated = generated + 1
                        print(string.format("  Saved %s (%d bytes)", filename, #responseBody))
                    else
                        failed = failed + 1
                        print("  ERROR: Could not write to " .. outPath)
                    end
                else
                    failed = failed + 1
                    print(string.format("  ERROR: HTTP %s — %s", tostring(code),
                                        tostring(responseBody):sub(1, 200)))
                end
            end
        end
    end

    print(string.format("Done. %d generated, %d skipped, %d failed.",
                        generated, skipped, failed))
    love.event.quit(failed > 0 and 1 or 0)
end
