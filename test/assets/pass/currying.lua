--[[
This test is two tests in one:
1. Ensure function closures work as expected.
2. The parser correctly evaluates currying.
    a. This includes chained function calls.
    b. Which in turn includes the special behavior for
        single arg string and table constructor.
--]]

function summer(x)
    return function(y)
        print(x+y)

        if y+"0" > 10 then
            print("y > 10")
            return function(a, b)
                print(a*b)
                return summer(a*b), x+y
            end
        end

        return summer(x+y), x+y

    end
end
sum = summer(0)

sum "1" "2" "3" "4" "5" (11) (3,2) "9"

-- Expect: 1
-- Expect: 3
-- Expect: 6
-- Expect: 10
-- Expect: 15
-- Expect: 26
-- Expect: y > 10
-- Expect: 6
-- Expect: 15