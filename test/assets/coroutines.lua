local function test1()
    local co = coroutine.create(function()
        for i = 1, 10 do
            print(i)
            coroutine.yield()
        end
    end)

    while coroutine.resume(co) do
        print('resuming')
    end
end

local function test2()
    -- create a coroutine
    local co = coroutine.create(function (value1,value2)
        local tempvar3 = 10
        print("coroutine section 1", value1, value2, tempvar3)
        -- yield the current execution
        local tempvar1 = coroutine.yield(value1+1,value2+1)
        tempvar3 = tempvar3 + value1
        print("coroutine section 2",tempvar1 ,tempvar2, tempvar3)
        -- yield the current execution	
        local tempvar1, tempvar2 = coroutine.yield(value1+value2, value1-value2)
        tempvar3 = tempvar3 + value1
        print("coroutine section 3",tempvar1, tempvar2, tempvar3)
        return value2, "end"
    end)

    -- resume the coroutines
    print("main", coroutine.resume(co, 3, 2))
    print("main", coroutine.resume(co, 12,14))
    print("main", coroutine.resume(co, 5, 6))
    print("main", coroutine.resume(co, 10, 20))
end

test2()