local A = {name='Alfred'}
local B = {name='Barry'}

setmetatable(A, {
    __concat = function(l, r) return l.name .. r end
})

setmetatable(B, {
    __concat = function(l, r) return l .. r.name end
})

-- Expect: AlfredBarry
print(A .. B)