local x = {value=10}
local y = 9

setmetatable(x, {
    __bxor = function(l, r)
        return x.value ~ r
    end
})

-- Expect: 3
print(x ~ y)