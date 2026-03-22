-- config.lua
-- App configuration + .env secret loading (mirrors Python config.py pattern)

local config = {}

-- Parse .env file from the project source directory
local contents = love.filesystem.read(".env")
if contents then
    for line in contents:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("=") then
            local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if key then config[key] = value end
        end
    end
end

-- API Keys (from .env)
config.OPENAI_API_KEY     = config.OPEN_AI_API_EMDR_KEY
config.ELEVENLABS_API_KEY = config.ELEVENLABS_API_EMDR_KEY

-- ElevenLabs Settings
config.ELEVENLABS_VOICE_ID  = "EXAVITQu4vr4xnSDxMaL"  -- Sarah voice (default premade, free-plan compatible)
config.ELEVENLABS_BASE_URL  = "https://api.elevenlabs.io/v1"
config.ELEVENLABS_MODEL_ID  = "eleven_multilingual_v2"

-- Speech speed settings (0.7–1.2, 1.0 = normal)
config.NOTICE_SPEECH_SPEED  = 0.9   -- "What did you notice?" (slightly slower for therapeutic context)

-- Session / processing loop
config.cycles                = 6    -- processing cycles per session
config.oscillations          = 3   -- full sweeps per cycle
config.oscillation_frequency = 1.0  -- Hz (sweeps per second)

return config
