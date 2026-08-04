local t1 = {'A', 'B', 'C', 'D'}

setmetatable(t1, {
    __call = function(a, b)
        local out = ""
        for _, v in pairs(a) do out = out .. v end
        for _, v in pairs(b) do out = out .. v end
        return out
    end
})

-- Expect: ABCDXYZ
print(t1{'X','Y','Z'})