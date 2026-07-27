local x = {value=13}

setmetatable(x, {
    __shl = function(l, r)
        return x.value << r
    end
})

-- Expect: 52
print(x << 2)