function foo()
    print("start")

    -- This is a syntax error:
    -- return "early exit"
    -- print("This is unreachable")

    -- This is the correct way to return early:
    do
        return "early exit"
    end

    -- Code here is unreachable because the do-end block returned
    print("This will not print")
end

-- Expect: start
foo()