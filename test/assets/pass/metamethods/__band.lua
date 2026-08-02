local x = {value=10}
local y = 9

setmetatable(x, {
    __band = function(l, r)
        return x.value & r
    end
})

-- Expect: 8
print(x & y)