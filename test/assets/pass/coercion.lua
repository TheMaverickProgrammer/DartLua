local x = "1" + "10"

-- Expect: 11
print(x)


-- Expect: number
print(type(x))

x = "99"

-- Expect: x > 10
if x+"0" > 10 then
    print "x > 10"
end

-- Expect: string
print(type(x))