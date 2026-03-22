local wav = {}

local function uint16_le(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

local function uint32_le(n)
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

--- Encode a LOVE SoundData object into a WAV file string.
-- @param soundData love.sound.SoundData
-- @return string  Complete WAV file contents
function wav.encode(soundData)
    local sampleRate = soundData:getSampleRate()
    local bitDepth = soundData:getBitDepth()
    local channels = soundData:getChannelCount()
    local sampleCount = soundData:getSampleCount()

    local bytesPerSample = bitDepth / 8
    local dataSize = sampleCount * channels * bytesPerSample
    local blockAlign = channels * bytesPerSample
    local byteRate = sampleRate * blockAlign

    local header = "RIFF"
        .. uint32_le(36 + dataSize)     -- file size - 8
        .. "WAVE"
        -- fmt sub-chunk
        .. "fmt "
        .. uint32_le(16)                -- sub-chunk size
        .. uint16_le(1)                 -- PCM format
        .. uint16_le(channels)
        .. uint32_le(sampleRate)
        .. uint32_le(byteRate)
        .. uint16_le(blockAlign)
        .. uint16_le(bitDepth)
        -- data sub-chunk
        .. "data"
        .. uint32_le(dataSize)

    -- SoundData inherits Data:getString() which returns raw PCM bytes
    return header .. soundData:getString()
end

return wav
