local x = {value=100}

setmetatable(x, {
    __unm = function(self)
        return -self.value
    end,
    __tostring = function(self)
        return tostring(self.value)
    end
})

-- Expect: -100
print(-x)