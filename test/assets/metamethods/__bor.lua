local x = {value=10}
local y = 9

setmetatable(x, {
    __bor = function(l, r)
        return x.value | r
    end
})

-- Expect: 11
print(x | y)