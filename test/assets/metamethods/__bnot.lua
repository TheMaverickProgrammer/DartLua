local x = {value=123}

setmetatable(x, {
    __bnot = function(self)
        return ~self.value
    end
})

-- Expect: -124
print(~x)