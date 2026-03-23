-- modules/transcript_list.lua
-- Sorted singly-linked list of {cycle, response_text} nodes.

local TranscriptList = {}
TranscriptList.__index = TranscriptList

function TranscriptList.new()
    return setmetatable({ head = nil, length = 0 }, TranscriptList)
end

--- Insert a node in cycle-sorted order.
function TranscriptList:insert(cycle, response_text)
    local node = { cycle = cycle, response_text = response_text, next = nil }

    if not self.head or cycle < self.head.cycle then
        node.next = self.head
        self.head = node
    else
        local cur = self.head
        while cur.next and cur.next.cycle < cycle do
            cur = cur.next
        end
        node.next = cur.next
        cur.next = node
    end

    self.length = self.length + 1
end

--- Iterator: for cycle, text in list:iter() do ... end
function TranscriptList:iter()
    local cur = self.head
    return function()
        if not cur then return nil end
        local cycle, text = cur.cycle, cur.response_text
        cur = cur.next
        return cycle, text
    end
end

--- Convert to a plain array of {cycle, response_text} tables.
function TranscriptList:toArray()
    local arr = {}
    for cycle, text in self:iter() do
        table.insert(arr, { cycle = cycle, response_text = text })
    end
    return arr
end

--- Serialize list to a text file.
function TranscriptList:save(filepath, timestamp)
    local f = io.open(filepath, "w")
    if not f then
        print("[TranscriptList] Failed to open file for writing: " .. filepath)
        return false
    end

    f:write("Session: " .. (timestamp or "unknown") .. "\n")
    f:write("Cycles: " .. self.length .. "\n")

    for cycle, text in self:iter() do
        f:write("\n--- Cycle " .. cycle .. " ---\n")
        f:write(text .. "\n")
    end

    f:close()
    return true
end

return TranscriptList
