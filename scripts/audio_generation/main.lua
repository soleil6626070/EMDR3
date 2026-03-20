-- scripts/audio_generation/main.lua
-- Generates TTS audio variants via ElevenLabs API.
-- Run from project root:  love scripts/audio_generation

-- ============================================================
-- CONFIGURE WHAT TO GENERATE HERE
-- ============================================================

local TEXT        = "What did you notice?"   -- The phrase to speak
local FILE_PREFIX = "what_noticed"           -- Output files: {prefix}_1.mp3, {prefix}_2.mp3, ...
local VARIANTS    = 3                        -- Number of audio variants to generate
local SPEED       = 0.8                      -- Speech speed (0.7 = slower, 1.0 = normal, 1.2 = faster)

-- ============================================================

function love.load()
    -- Resolve project root
    local handle = io.popen("pwd")
    local cwd = handle:read("*l")
    handle:close()
    local source = love.filesystem.getSource()
    local projectRoot
    if source:sub(1, 1) == "/" then
        projectRoot = source:match("^(.+)/[^/]+/[^/]+$")
    else
        projectRoot = cwd
    end

    -- Load native HTTPS module
    package.cpath = projectRoot .. "/lib/?.so;"
                 .. projectRoot .. "/lib/?.dll;"
                 .. package.cpath
    local https = require("https")

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

    -- ElevenLabs config (matches config.lua)
    local voice_id = "EXAVITQu4vr4xnSDxMaL"  -- Sarah (default premade, free-plan compatible)
    local model_id = "eleven_multilingual_v2"
    local base_url = "https://api.elevenlabs.io/v1"

    -- Ensure output directory exists
    local audioDir = projectRoot .. "/resources/audio"
    os.execute('mkdir -p "' .. audioDir .. '"')

    -- Generate variants
    local escaped_text = TEXT:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
    local body = string.format(
        '{"text":"%s","model_id":"%s","voice_settings":{"stability":0.5,"similarity_boost":0.75,"speed":%.1f}}',
        escaped_text, model_id, SPEED
    )

    for n = 1, VARIANTS do
        local filename = FILE_PREFIX .. "_" .. n .. ".mp3"
        local outPath = audioDir .. "/" .. filename

        print(string.format("[%d/%d] Generating %s...", n, VARIANTS, filename))

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
                print(string.format("  Saved %s (%d bytes)", filename, #responseBody))
            else
                print(string.format("  ERROR: Could not write to %s", outPath))
            end
        else
            print(string.format("  ERROR: HTTP %s — %s", tostring(code), tostring(responseBody)))
        end
    end

    print("Done!")
    love.event.quit()
end
