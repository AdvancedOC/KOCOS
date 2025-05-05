local terminal = require("terminal")
for i=0,255 do
    terminal.sendCSI("m", "48", "5", tostring(i))
    io.write(" ")
    io.flush()
end
terminal.reset()
