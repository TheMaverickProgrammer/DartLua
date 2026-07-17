-- Demonstrates how to read `args`
-- from the main driver.
print('Your user input was:')
for k,v in pairs(arg) do
    print(k..'='..tostring(v))
end