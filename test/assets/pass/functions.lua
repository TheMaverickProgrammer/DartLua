local t = {}
function t:foo(x)
    print(self)
    print(x)
end

function t.bar(x, y)
    print(x)
    print(y)
end

-- Expect: table
-- Expect: 100
t:foo(100)

-- Expect: table
-- Expect: 4
t:bar(4)