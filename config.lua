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

-- ElevenLabs Conversational AI Agent
config.ELEVENLABS_AGENT_ID  = config.ELEVENLABS_AGENT_ID_EMDR or ""
config.AGENT_MAX_DURATION   = 600   -- seconds (10 min safety timeout)
config.AGENT_OUTPUT_DIR     = "output_data"

-- Whisper (local transcription)
config.WHISPER_BIN   = "bin/whisper-cli"
config.WHISPER_MODEL = "models/ggml-small.en.bin"

-- Session / processing loop
config.cycles                = 6    -- processing cycles per session
config.oscillations          = 6   -- full sweeps per cycle
config.oscillation_frequency = 1.0  -- Hz (sweeps per second)

-- Slowdown: critically damped spring clamped to center (no overshoot)
config.slowdown_oscillations = 1     -- last N oscillations decelerate
config.slowdown_stiffness    = 2.2   -- spring natural frequency (higher = faster return to center)

-- Breathing animation after oscillation stops at center
config.breathe_in_duration   = 4.0   -- seconds for inhale (circle grows)
config.breathe_out_duration  = 4.0   -- seconds for exhale (circle shrinks)
config.breathe_max_radius    = 96    -- max radius during inhale (4x default RADIUS of 24)

return config
