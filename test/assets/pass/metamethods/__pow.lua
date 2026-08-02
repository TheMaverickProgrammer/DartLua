local A = {
    quantity = 30
    units = 'm/s'
}

local mt = {
    __pow = function(l, r)
        local q = 1
        for i=1,r do
            q = q * l.quantity
        end
        local out  = {quantity=q, units=l.units..'^'..tostring(r)}
        setmetatable(out, mt)
        return out
    end,
    __tostring = function(self)
        return tostring(self.quantity)..' '..self.units
    end
}

setmetatable(A, mt)

-- Expect: 900 m/s^2
print(A ^ 2)