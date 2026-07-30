local suit = libRequire("love-suit", "init")

if Registry and Registry.registerGlobal then
    Registry.registerGlobal("SUIT", suit)
end

return suit
