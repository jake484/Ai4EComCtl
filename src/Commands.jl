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
从PLC读取数据（模拟实现）
"""
function read_from_plc(cfg::UpdateConfig)::Dict{String,Any}
    # 实际应用中这里会使用Modbus或其他协议与PLC通信
    sleep(rand() * cfg.timeout / 2)  # 模拟网络延迟

    # 模拟读取完整的系统数据
    return Dict(
        "main_pressure" => 6.5 + randn() * 0.1,  # 总管压力带随机波动
        "compressors" => [
            Dict("id" => 1, "state" => 3, "outlet_pressure" => 6.8, "fault_code" => nothing, "run_time" => 12500.0, "load_time" => 9800.0),
            Dict("id" => 2, "state" => 3, "outlet_pressure" => 6.7, "fault_code" => nothing, "run_time" => 11200.0, "load_time" => 8700.0),
            Dict("id" => 3, "state" => 1, "outlet_pressure" => 0.0, "fault_code" => nothing, "run_time" => 5600.0, "load_time" => 4200.0)
        ],
        "dryers" => [
            Dict("id" => 1, "state" => 2, "fault_code" => nothing, "run_time" => 10000.0),
            Dict("id" => 2, "state" => 1, "fault_code" => nothing, "run_time" => 8000.0)
        ],
        "params" => Dict(
            # 压力参数
            "p_low_alarm" => 5.9,
            "p_low" => 6.2,
            "p_set" => 6.6,
            "p_high" => 6.9,
            "p_high_alarm" => 7.2,
            "delta_p_drop" => 0.06,
            "delta_p_rise" => 0.06,
            
            # 时间参数
            "pressure_delay" => 5.0,
            "comp_load_interval" => 10.0,
            "comp_unload_interval" => 10.0,
            "comp_start_interval" => 30.0,
            "comp_stop_protect" => 300.0,
            "comp_unload_to_stop" => 600.0,
            
            # 压缩机配置
            "comp_screw_priority" => true,
            "comp_balance_load" => true,
            "comp_priority" => [1, 2, 3, 4, 5],
            "comp_interlock" => [true, true, true, true, true],
            
            # 干燥机参数
            "dryer_balance_load" => true,
            "dryer_priority" => [1, 2, 3, 4],
            "dryer_interlock" => [true, true, true, true],
            
            # 场景化参数
            "var_load_threshold" => 90.0,
            "var_unload_threshold" => 50.0,
            "add_delay" => 30.0,
            "remove_delay" => 120.0,
            "ultra_low_delay" => 15.0,
            "ultra_high_delay" => 2.0
        ),
        "flags" => Dict(
            "emergency_flag" => false,
            "new_start_flag" => false,
            "new_load_flag" => false,
            "new_unload_flag" => false
        )
    )
end

"""
从数据中心读取数据（模拟实现）
"""
function read_from_data_center(cfg::UpdateConfig)::Dict{String,Any}
    # 实际应用中这里会通过HTTP/HTTPS调用API
    sleep(rand() * cfg.timeout / 2)  # 模拟网络延迟

    return Dict(
        "main_pressure" => 6.5 + randn() * 0.15,  # 数据中心数据可能波动更大
        "compressors" => [
            Dict("id" => 1, "run_time" => 12500.0, "load_time" => 9800.0),
            Dict("id" => 2, "run_time" => 11200.0, "load_time" => 8700.0),
            Dict("id" => 3, "run_time" => 5600.0, "load_time" => 4200.0)
        ],
        "dryers" => [
            Dict("id" => 1, "run_time" => 10000.0),
            Dict("id" => 2, "run_time" => 8000.0)
        ],
        "params" => Dict(
            # 压力参数
            "p_set" => 6.6,
            "p_low" => 6.2,
            "p_high" => 6.9,
            
            # 时间参数
            "comp_stop_protect" => 300.0,
            "comp_unload_to_stop" => 600.0,
            
            # 压缩机配置
            "comp_priority" => [1, 2, 3, 4, 5]
        ),
        "system_status" => "normal"
    )
end

"""
更新系统状态数据
"""
function update_system_data!(sys::EnhancedAirSystem)::Bool
    try
        # 根据数据源类型读取数据
        raw_data = if sys.update_cfg.data_source == PLC
            read_from_plc(sys.update_cfg)
        elseif sys.update_cfg.data_source == DataCenter
            read_from_data_center(sys.update_cfg)
        else  # Mixed模式，合并两种数据源
            plc_data = read_from_plc(sys.update_cfg)
            dc_data = read_from_data_center(sys.update_cfg)
            merge(dc_data, plc_data)  # PLC数据覆盖数据中心同名字段
        end

        # 更新总管压力
        if haskey(raw_data, "main_pressure")
            sys.core.main_pressure = raw_data["main_pressure"]
        end

        # 更新压缩机状态
        if haskey(raw_data, "compressors")
            for comp_data in raw_data["compressors"]
                comp = get_compressor(sys.core, comp_data["id"])
                if !isnothing(comp)
                    # 更新状态
                    if haskey(comp_data, "state")
                        comp.state = State(comp_data["state"])
                    end
                    # 更新出口压力
                    if haskey(comp_data, "outlet_pressure")
                        comp.outlet_pressure = comp_data["outlet_pressure"]
                    end
                    # 更新故障码
                    if haskey(comp_data, "fault_code")
                        comp.fault_code = comp_data["fault_code"]
                    end
                    # 更新运行时间
                    if haskey(comp_data, "run_time")
                        comp.run_time = comp_data["run_time"]
                    end
                    # 更新加载时间
                    if haskey(comp_data, "load_time")
                        comp.load_time = comp_data["load_time"]
                    end
                end
            end
        end

        # 更新干燥机状态
        if haskey(raw_data, "dryers")
            for dryer_data in raw_data["dryers"]
                dryer = get_dryer(sys.core, dryer_data["id"])
                if !isnothing(dryer)
                    # 更新状态
                    if haskey(dryer_data, "state")
                        dryer.state = State(dryer_data["state"])
                    end
                    # 更新故障码
                    if haskey(dryer_data, "fault_code")
                        dryer.fault_code = dryer_data["fault_code"]
                    end
                    # 更新运行时间
                    if haskey(dryer_data, "run_time")
                        dryer.run_time = dryer_data["run_time"]
                    end
                end
            end
        end

        # 更新系统参数（如果允许）
        if sys.update_cfg.param_update_enabled && haskey(raw_data, "params")
            update_system_params!(sys.core.params, raw_data["params"])
        end

        # 更新系统标志位
        if haskey(raw_data, "flags")
            update_system_flags!(sys.core, raw_data["flags"])
        end

        # 记录最后更新时间
        sys.last_update_time = now()
        return true

    catch e
        @error "Data update failed" exception = e
        push!(sys.core.alarms, (now(), "Data update failed: $(sprint(showerror, e))"))
        return false
    end
end

"""
更新系统参数
"""
function update_system_params!(params::SystemParams, param_data::Dict{String,Any})
    # 获取SystemParams的所有字段名
    field_names = fieldnames(SystemParams)
    
    for field_name in field_names
        field_str = string(field_name)
        if haskey(param_data, field_str)
            try
                # 获取字段类型
                field_type = fieldtype(SystemParams, field_name)
                # 转换数据类型并设置字段值
                converted_value = convert_param_value(field_type, param_data[field_str])
                setproperty!(params, field_name, converted_value)
                @info "Updated system parameter: $field_str = $converted_value"
            catch e
                @warn "Failed to update parameter: $field_str. Error: $e"
            end
        end
    end
end

"""
转换参数值到正确的类型
"""
function convert_param_value(::Type{T}, value) where T
    if T <: Vector
        # 处理向量类型
        if isa(value, Vector)
            return convert(T, value)
        elseif isa(value, AbstractArray)
            return T(value)
        else
            @warn "Cannot convert $value to $T"
            throw(ArgumentError("Cannot convert $value to $T"))
        end
    else
        # 处理标量类型
        return convert(T, value)
    end
end

# 为常见类型提供特化
function convert_param_value(::Type{Vector{Int}}, value)
    if isa(value, Vector{Int})
        return value
    elseif isa(value, Vector)
        return convert(Vector{Int}, value)
    else
        @warn "Cannot convert $value to Vector{Int}"
        throw(ArgumentError("Cannot convert $value to Vector{Int}"))
    end
end

function convert_param_value(::Type{Vector{Bool}}, value)
    if isa(value, Vector{Bool})
        return value
    elseif isa(value, Vector)
        return convert(Vector{Bool}, value)
    else
        @warn "Cannot convert $value to Vector{Bool}"
        throw(ArgumentError("Cannot convert $value to Vector{Bool}"))
    end
end

"""
更新系统标志位
"""
function update_system_flags!(sys::AirCompressorSystem, flag_data::Dict{String,Any})
    flag_fields = ["emergency_flag", "new_start_flag", "new_load_flag", "new_unload_flag"]
    
    for flag_field in flag_fields
        if haskey(flag_data, flag_field)
            try
                flag_value = convert(Bool, flag_data[flag_field])
                setproperty!(sys, Symbol(flag_field), flag_value)
                @info "Updated system flag: $flag_field = $flag_value"
            catch e
                @warn "Failed to update flag: $flag_field. Error: $e"
            end
        end
    end
end

# 添加缺失的辅助函数
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
数据更新定时任务
"""
function data_update_task(sys::EnhancedAirSystem)
    @info "Data update task started, interval: $(sys.update_cfg.update_interval) seconds"

    while true
        try
            # 尝试多次读取数据
            success = false
            for i in 1:sys.update_cfg.retry_count
                success = update_system_data!(sys)
                if success
                    break
                end
                @warn "Data update failed, retrying ($i/$sys.update_cfg.retry_count)"
                sleep(0.5)
            end

            if !success
                @error "Max retries reached, data update failed"
            end

        catch e
            @error "Data update task error" exception = e
        end

        # 等待下一次更新
        sleep(sys.update_cfg.update_interval)
    end
end

"""
启动数据更新任务
"""
function start_data_update(sys::EnhancedAirSystem)
    if isnothing(sys.update_task) || istaskdone(sys.update_task)
        sys.update_task = @async data_update_task(sys)
        @info "Data update task started"
    else
        @warn "Data update task is already running"
    end
end

"""
停止数据更新任务
"""
function stop_data_update(sys::EnhancedAirSystem)
    if !isnothing(sys.update_task) && istaskrunning(sys.update_task)
        Base.throwto(sys.update_task, InterruptException())
        sys.update_task = nothing
        @info "Data update task stopped"
    end
end

"""
添加指令到队列
"""
function enqueue_command(sys::EnhancedAirSystem, command::Dict{String,Any}, priority::Int=5)
    # 指令格式示例: {"type": "start_compressor", "id": 1, "params": {...}}
    enqueue!(sys.command_queue, command, priority)
    @info "Command enqueued: $(command["type"]) ID=$(command["id"]) priority=$priority"
end

"""
发送指令到设备（模拟实现）
"""
function send_command_to_device(command::Dict{String,Any})::Tuple{Bool,String}
    # 实际应用中这里会根据设备类型发送相应协议的指令
    device_type = split(command["type"], "_")[end]  # 从指令类型提取设备类型
    @info "Sending command to $(device_type) ID=$(command["id"]): $(command["type"])"

    # 模拟指令发送延迟
    sleep(0.1 + rand() * 0.3)

    # 模拟95%的成功率
    if rand() < 0.95
        return (true, "Command executed successfully")
    else
        return (false, "Device unresponsive")
    end
end

"""
指令处理任务
"""
function command_processing_task(sys::EnhancedAirSystem)
    @info "Command processing task started"

    while true
        try
            # 检查是否允许下发指令
            if !sys.command_cfg.enabled
                sleep(1.0)
                continue
            end

            # 检查是否有指令需要处理
            if !isempty(sys.command_queue)
                # 检查指令下发间隔
                time_since_last = Second(now() - sys.last_command_time).value
                if time_since_last < sys.command_cfg.min_interval
                    sleep(sys.command_cfg.min_interval - time_since_last)
                end

                # 获取优先级最高的指令
                command = dequeue!(sys.command_queue)

                # 处理指令
                success = false
                msg = ""
                for i in 1:sys.command_cfg.retry_count
                    success, msg = send_command_to_device(command)
                    if success
                        break
                    end
                    @warn "Command send failed, retrying ($i/$sys.command_cfg.retry_count): $msg"
                    sleep(0.5)
                end

                # 记录结果
                if success
                    @info "Command processed successfully: $(command["type"]) ID=$(command["id"])"
                    sys.last_command_time = now()
                    push!(sys.core.alarms, (now(), "Command succeeded: $(command["type"]) ID=$(command["id"])"))
                else
                    @error "Command processing failed: $(command["type"]) ID=$(command["id"]) Reason: $msg"
                    push!(sys.core.alarms, (now(), "Command failed: $(command["type"]) ID=$(command["id"]) Reason: $msg"))
                end
            else
                # 没有指令时短暂休眠
                sleep(0.1)
            end

        catch e
            @error "Command processing task error" exception = e
            sleep(1.0)
        end
    end
end

"""
启动指令处理任务
"""
function start_command_processing(sys::EnhancedAirSystem)
    if isnothing(sys.command_task) || istaskdone(sys.command_task)
        sys.command_task = @async command_processing_task(sys)
        @info "Command processing task started"
    else
        @warn "Command processing task is already running"
    end
end

"""
停止指令处理任务
"""
function stop_command_processing(sys::EnhancedAirSystem)
    if !isnothing(sys.command_task) && istaskrunning(sys.command_task)
        Base.throwto(sys.command_task, InterruptException())
        sys.command_task = nothing
        @info "Command processing task stopped"
    end
end

"""
设置数据更新间隔
"""
function set_update_interval!(sys::EnhancedAirSystem, interval::Float64)
    if interval > 0
        sys.update_cfg.update_interval = interval
        @info "Data update interval set to: $interval seconds"
        return true
    end
    @error "Invalid update interval: $interval seconds"
    return false
end

"""
设置数据源
"""
function set_data_source!(sys::EnhancedAirSystem, source::DataSource)
    sys.update_cfg.data_source = source
    @info "Data source set to: $source"
    return true
end

"""
主控制流程：数据更新 -> 逻辑计算 -> 指令下发
"""
function main_control_loop(sys::EnhancedAirSystem, interval::Float64=1.0)
    @info "Main control loop started, interval: $interval seconds"

    # 确保数据更新和指令处理任务已启动
    start_data_update(sys)
    start_command_processing(sys)

    try
        while true
            # 等待数据更新完成
            since_last_update = Second(now() - sys.last_update_time).value
            if since_last_update > 2 * sys.update_cfg.update_interval
                @warn "Data not updated for a long time, potential issue"
                push!(sys.core.alarms, (now(), "Data stale - last update $(since_last_update) seconds ago"))
            end

            # 执行压缩机联锁逻辑计算
            compressor_interlock_logic(sys.core)

            # 根据计算结果生成指令（示例）
            # enqueue_command(sys, {"type": "start_compressor", "id": 3}, 5)

            # 等待下一个周期
            sleep(interval)
        end
    finally
        # 停止所有任务
        stop_data_update(sys)
        stop_command_processing(sys)
    end
end
