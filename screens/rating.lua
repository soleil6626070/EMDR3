-- screens/rating.lua
-- SUD (Subjective Units of Disturbance) 0–10 rating screen.
-- Returns a factory: require("screens.rating")("pre") / ("post").
-- "pre"  — after target selection, before the session starts. Confirming
--          starts the session and creates the session record.
-- "post" — after the final cycle. Confirming writes post_sud and closes
--          out the session.

local config         = require("config")
local session        = require("modules.session")
local session_record = require("modules.session_record")

return function(kind)
    local rating = {}

    local fontTitle, fontBig, fontScale, fontHint
    local value
    local recordPath   -- captured on load; session state is reset before we leave

    function rating.load()
        fontTitle = love.graphics.newFont(24)
        fontBig   = love.graphics.newFont(72)
        fontScale = love.graphics.newFont(16)
        fontHint  = love.graphics.newFont(14)
        value = 5
        if kind == "post" then
            recordPath = session_record.currentPath()
        end
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
        local line1
        if kind == "pre" then
            line1 = "Bring the target memory to mind."
        else
            line1 = "Returning to the memory now..."
        end
        local line2 = "How disturbing does it feel right now?"
        love.graphics.print(line1, (W - fontTitle:getWidth(line1)) / 2, H * 0.18)
        love.graphics.print(line2, (W - fontTitle:getWidth(line2)) / 2, H * 0.18 + 40)

        -- Selected value, large
        love.graphics.setFont(fontBig)
        love.graphics.setColor(1, 1, 1)
        local num = tostring(value)
        love.graphics.print(num, (W - fontBig:getWidth(num)) / 2, H * 0.36)

        -- Scale: 11 dots along a line
        local scaleY = H * 0.62
        local left   = W * 0.15
        local right  = W * 0.85
        love.graphics.setColor(0.25, 0.28, 0.38)
        love.graphics.setLineWidth(2)
        love.graphics.line(left, scaleY, right, scaleY)

        for i = 0, 10 do
            local px = left + (right - left) * (i / 10)
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
        love.graphics.print("0 — no disturbance", left - 10, scaleY + 24)
        local lbl = "10 — worst imaginable"
        love.graphics.print(lbl, right - fontScale:getWidth(lbl) + 10, scaleY + 24)

        -- Hints
        love.graphics.setFont(fontHint)
        love.graphics.setColor(0.4, 0.4, 0.5)
        local back = (kind == "pre") and "Escape — back" or "Escape — skip rating"
        local hint = "← → adjust   0–9 set directly   Enter — confirm   " .. back
        love.graphics.print(hint, (W - fontHint:getWidth(hint)) / 2, H - 36)
    end

    local function finishSession(post_sud)
        if post_sud then
            session_record.finish(recordPath, post_sud)
        end
        session.clearOngoing()
        session.reset()
        switchScreen("menu")
    end

    function rating.keypressed(k)
        if k == "escape" then
            if kind == "pre" then
                switchScreen("target_select")
            else
                finishSession(nil)  -- skipped: record keeps post_sud = null
            end
            return
        end

        local digit = k:match("^(%d)$") or k:match("^kp(%d)$")

        if k == "left" then
            value = math.max(0, value - 1)
        elseif k == "right" then
            value = math.min(10, value + 1)
        elseif digit then
            value = tonumber(digit)
        elseif k == "return" or k == "kpenter" then
            if kind == "pre" then
                session.start(config.cycles)
                session_record.begin(value)
                switchScreen("oscillating")
            else
                finishSession(value)
            end
        end
    end

    return rating
end
