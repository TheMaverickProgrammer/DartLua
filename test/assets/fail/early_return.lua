function foo()
    print("start")

    -- This is a syntax error:
    return "early exit"
    print("This is unreachable")
end

-- Expect: [   6:5  ] Keyword "return" must be last in a block.