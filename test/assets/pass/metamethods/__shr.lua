local x = {value=13}

setmetatable(x, {
    __shr = function(l, r)
        return x.value >> r
    end
})

-- Expect: 3
print(x >> 2)