local x = 0
for i=0,10 do
    x = x + 1
    if x > 5 then
        break
    end
end

-- Expect:  [  10:1  ] Keyword "break" outside of loop.
break