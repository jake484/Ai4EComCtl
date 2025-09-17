module Ai4EComCtl

using Dates, DataStructures, Logging

include("Modes.jl")
include("Structs.jl")
include("MultCtl.jl")

export AirCompressorSystem, compressor_interlock_logic, start_compressor_interlock_task,
remote_start_compressor,
    remote_auto_regulate_compressor, remote_manual_unload_compressor,
    remote_stop_compressor, remote_start_dryer, remote_stop_dryer,
    get_compressor, get_dryer, init_system, State, ControlMode, SystemMode,
    RUNNING, STOPPED, AUTO_REGULATED, MANUAL_UNLOADED,
    REMOTE_CONTROL, AUTO_INTERLOCK, Compressor, Dryer

# 导出新函数
export generate_system_optimization_suggestion

end # module Ai4EComCtl