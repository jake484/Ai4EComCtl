module Ai4EComCtl

using Dates, DataStructures, Logging

include("Modes.jl")
include("Structs.jl")
include("SingleCtl.jl")
include("MultCtl.jl")
include("Commands.jl")

greet() = print("Hello World!")

export greet

end # module Ai4EComCtl
