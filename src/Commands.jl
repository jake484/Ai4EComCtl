"""
数据源类型枚举
"""
@enum DataSource PLC = 1 DataCenter = 2 Mixed = 3

"""
数据更新配置结构体（使用Base.@kwdef定义默认值）
"""
Base.@kwdef mutable struct UpdateConfig
    data_source::DataSource = PLC               # 数据源类型，默认PLC
    update_interval::Float64 = 1.0              # 数据更新间隔（秒），默认1秒
    plc_address::String = "192.168.1.100:502"   # PLC地址
    data_center_url::String = "http://datacenter:8080/api"  # 数据中心API地址
    timeout::Float64 = 2.0                      # 数据读取超时（秒）
    retry_count::Int = 3                        # 读取失败重试重试次数
    param_update_enabled::Bool = true           # 是否允许更新系统参数
    priority_threshold::Int = 5                 # 数据优先级阈值（用于混合模式）
end

"""
指令下发配置结构体
"""
Base.@kwdef mutable struct CommandConfig
    enabled::Bool = true                 # 是否允许下发指令
    min_interval::Float64 = 0.5          # 指令下发最小间隔（秒）
    batch_support::Bool = true           # 是否支持批量指令
    retry_count::Int = 2                 # 下发失败重试次数
    confirm_timeout::Float64 = 3.0       # 等待设备确认超时（秒）
    emergency_priority::Int = 0          # 紧急指令优先级（0-最高）
end

"""
扩展系统结构体，增加数据和指令配置
"""
Base.@kwdef mutable struct EnhancedAirSystem
    core::AirCompressorSystem = init_system()  # 核心系统状态
    update_cfg::UpdateConfig = UpdateConfig()   # 数据更新配置
    command_cfg::CommandConfig = CommandConfig()  # 指令下发配置
    last_update_time::DateTime = now() - Second(10)  # 最后更新时间
    last_command_time::DateTime = now() - Second(10) # 最后指令下发时间
    command_queue::PriorityQueue{Any,Int} = PriorityQueue{Any,Int}()  # 指令队列
    update_task::Union{Task,Nothing} = nothing  # 数据更新任务
    command_task::Union{Task,Nothing} = nothing  # 指令处理任务
end


"""
获取干燥机（辅助函数）
"""
function get_dryer(sys::AirCompressorSystem, dryer_id::Int)::Union{Dryer, Nothing}
    for dryer in sys.dryers
        if dryer.id == dryer_id
            return dryer
        end
    end
    return nothing
end

"""
初始化系统函数
"""
function init_system()::AirCompressorSystem
    sys = AirCompressorSystem()
    sys.mode = AUTO_INTERLOCK
    
    # 初始化6台压缩机
    for i in 1:6
        comp = Compressor(id=i)
        comp.mode = REMOTE_CONTROL
        push!(sys.compressors, comp)
    end
    
    # 初始化6台干燥机
    for i in 1:6
        dryer = Dryer(id=i)
        dryer.mode = REMOTE_CONTROL
        push!(sys.dryers, dryer)
    end
    
    return sys
end