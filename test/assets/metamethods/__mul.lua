local A = {token='[]|'}

setmetatable(A, {
    __mul = function(l, r)
        local out = l.token
        for i = 1, r-1 do
            out = out .. l.token
        end

        return out
    end
})

-- Expect: []|[]|[]|
print(A * 3)