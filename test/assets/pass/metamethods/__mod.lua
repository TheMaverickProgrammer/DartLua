local x = {value=13}
local y = 3

setmetatable(x, {
    __mod = function(l, r)
        return l.value%r
    end
})

-- Expect: 1
print(x%y)