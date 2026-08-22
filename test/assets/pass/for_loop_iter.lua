function list_iter (t)
    local i = 0
    local n = #t
    return function ()
        i = i + 1
        if i <= n then return t[i] end
    end
end

t = {10, 20, 30}

-- Expect: 10
-- Expect: 20
-- Expect: 30
for element in list_iter(t) do
    print(element)
end

function iter (a, i)
    i = i + 1
    local v = a[i]
    if v then
    return i, v
    end
end

function my_ipairs (a)
    return iter, a, 0
end

-- Expect: 1 10
-- Expect: 2 20
-- Expect: 3 30
for i, v in my_ipairs(t) do
    print(i, v)
end

function my_pairs (t)
    return next, t, nil
end

t = {
    M="Monday",
    T="Tuesday",
    W="Wednesday",
    R="Thursday",
    F="Friday",
    Sa="Saturday",
    Su="Sunday"
}
-- Expect: M Monday
-- Expect: T Tuesday
-- Expect: W Wednesday
-- Expect: R Thursday
-- Expect: F Friday
-- Expect: Sa Saturday
-- Expect: Su Sunday
for k, v in next, t do
    print(k, v)
end