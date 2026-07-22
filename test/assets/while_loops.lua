function foo()
    return false
end

function bar()
    return false, true
end

function doh()
    return {false, true}
end

function ray()
    return true, false
end

function mee()
    return true
end

-- not expected to run
local i = 5
while(foo() and i > 0) do
    i = i - 1
    print('shouldn\'t be here!')
end

-- not expected to run
i = 5
while(bar() and i > 0) do
    i = i - 1
    print('shouldn\'t be here!')
end

-- OK
i = 5
while(doh() and i > 0) do
    print('here1 x'..i)
    i = i - 1
end

-- OK
i = 5
while(ray() and i > 0) do
    print('here2 x'..i)
    i = i - 1
end

-- OK
i = 5
while(mee() and i > 0) do
    print('here3 x'..i)
    i = i - 1
end