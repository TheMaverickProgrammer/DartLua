local x = {value=3}
local y = 0

setmetatable(x, {
    __div = function(l, r)
        if r == 0 then
            return 'Attempt to divide by zero!'
        end
        return l.value/r
    end
})

-- Expect: Attempt to divide by zero!
print(x/y)