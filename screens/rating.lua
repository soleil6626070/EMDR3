-- screens/rating.lua
-- Numeric rating screen factory (SUD, VoC, ...).
-- Returns a factory taking either a preset name or an options table:
--   require("screens.rating")("pre") / ("post")   — the session SUD screens
--   require("screens.rating")({ min=1, max=7, default=4, title_lines={...},
--       anchor_min="...", anchor_max="...", escape_label="Escape — back",
--       on_load=fn, on_confirm=fn(value), on_escape=fn })
-- "pre"  — after target selection, before the session starts. Confirming
--          starts the session and creates the session record.
-- "post" — after the final cycle. Confirming writes post_sud and closes
--          out the session.

local config         = require("config")
local session        = require("modules.session")
local session_record = require("modules.session_record")

local function presetPre()
    return {
        min = 0, max = 10, default = 5,
        title_lines  = { "Bring the target memory to mind.",
                         "How disturbing does it feel right now?" },
        anchor_min   = "0 — no disturbance",
        anchor_max   = "10 — worst imaginable",
        escape_label = "Escape — back",
        on_confirm = function(value)
            session.start(config.cycles)
            session_record.begin(value)
            switchScreen("oscillating")
        end,
        on_escape = function()
            switchScreen("target_select")
        end,
    }
end

local function presetPost()
    local recordPath   -- captured on load; session state is reset before we leave

    local function finishSession(post_sud)
        if post_sud then
            session_record.finish(recordPath, post_sud)
        end
        session.clearOngoing()
        session.reset()
        switchScreen("menu")
    end

    return {
        min = 0, max = 10, default = 5,
        title_lines  = { "Returning to the memory now...",
                         "How disturbing does it feel right now?" },
        anchor_min   = "0 — no disturbance",
        anchor_max   = "10 — worst imaginable",
        escape_label = "Escape — skip rating",
        on_load = function()
            recordPath = session_record.currentPath()
        end,
        on_confirm = function(value)
            finishSession(value)
        end,
        on_escape = function()
            finishSession(nil)  -- skipped: record keeps post_sud = null
        end,
    }
end

local PRESETS = { pre = presetPre, post = presetPost }

return function(kindOrOpts)
    local opts
    if type(kindOrOpts) == "string" then
        opts = PRESETS[kindOrOpts]()
    else
        opts = kindOrOpts
    end

    local rating = {}

    local fontTitle, fontBig, fontScale, fontHint
    local value

    function rating.load()
        fontTitle = love.graphics.newFont(24)
        fontBig   = love.graphics.newFont(72)
        fontScale = love.graphics.newFont(16)
        fontHint  = love.graphics.newFont(14)
        value = opts.default
        if opts.on_load then opts.on_load() end
    end

    function rating.update(dt) end

    function rating.draw()
        local W = love.graphics.getWidth()
        local H = love.graphics.getHeight()

        love.graphics.setBackgroundColor(0.05, 0.05, 0.07)
        love.graphics.clear()

        -- Question
        love.graphics.setFont(fontTitle)
        love.graphics.setColor(0.85, 0.90, 1.0)
        for i, line in ipairs(opts.title_lines) do
            love.graphics.print(line, (W - fontTitle:getWidth(line)) / 2,
                                H * 0.18 + (i - 1) * 40)
        end

        -- Selected value, large
        love.graphics.setFont(fontBig)
        love.graphics.setColor(1, 1, 1)
        local num = tostring(value)
        love.graphics.print(num, (W - fontBig:getWidth(num)) / 2, H * 0.36)

        -- Scale: one dot per step along a line
        local scaleY = H * 0.62
        local left   = W * 0.15
        local right  = W * 0.85
        love.graphics.setColor(0.25, 0.28, 0.38)
        love.graphics.setLineWidth(2)
        love.graphics.line(left, scaleY, right, scaleY)

        for i = opts.min, opts.max do
            local px = left + (right - left) * ((i - opts.min) / (opts.max - opts.min))
            if i == value then
                love.graphics.setColor(0.72, 0.11, 0.20)
                love.graphics.circle("fill", px, scaleY, 12)
            else
                love.graphics.setColor(0.35, 0.40, 0.52)
                love.graphics.circle("fill", px, scaleY, 6)
            end
        end

        -- Anchor labels
        love.graphics.setFont(fontScale)
        love.graphics.setColor(0.5, 0.55, 0.65)
        love.graphics.print(opts.anchor_min, left - 10, scaleY + 24)
        love.graphics.print(opts.anchor_max,
                            right - fontScale:getWidth(opts.anchor_max) + 10, scaleY + 24)

        -- Hints
        love.graphics.setFont(fontHint)
        love.graphics.setColor(0.4, 0.4, 0.5)
        local digits = opts.min .. "–" .. math.min(opts.max, 9)
        local hint = "← → adjust   " .. digits .. " set directly   Enter — confirm   "
                     .. opts.escape_label
        love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
    end

    function rating.keypressed(k)
        if k == "escape" then
            opts.on_escape()
            return
        end

        local digit = k:match("^(%d)$") or k:match("^kp(%d)$")

        if k == "left" then
            value = math.max(opts.min, value - 1)
        elseif k == "right" then
            value = math.min(opts.max, value + 1)
        elseif digit then
            local n = tonumber(digit)
            if n >= opts.min and n <= opts.max then
                value = n
            end
        elseif k == "return" or k == "kpenter" then
            opts.on_confirm(value)
        end
    end

    return rating
end
