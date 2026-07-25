local A = '[]|'

setmetatable(A, {
    __mul = function(l, r)
        local token = l
        for i = 1, r-1 do
            l = token .. l
        end

        return l
    end
})

-- Expect: []|[]|[]|
print(A * 3)