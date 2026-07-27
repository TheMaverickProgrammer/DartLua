local s = "hello, world!"

-- Expect: 13
print(#s)

local t = {}

-- Expect: 0
print(#t)

setmetatable(t, {
    __len = function(self)
        return "a number? :)"
    end
})

-- Expect: a number? :)
print(#t)