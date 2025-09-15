"""
更新总管压力历史并维护数据窗口（只保留最近N条记录用于趋势分析）
"""
function update_pressure_history!(sys::AirCompressorSystem, max_points::Int=10)
    # 移除超出窗口的数据
    if length(sys.pressure_history) > max_points
        sys.pressure_history = sys.pressure_history[end-max_points+1:end]
    end
end

"""
计算压力变化率（Bar/秒）
返回值：(当前压力, 压力变化率)
"""
function calculate_pressure_trend(sys::AirCompressorSystem)::Tuple{Float64, Float64}
    if length(sys.pressure_history) < 2
        return (sys.main_pressure, 0.0)  # 数据不足时返回0变化率
    end
    
    # 取最近两个时间点的压力计算变化率
    (t1, p1) = sys.pressure_history[end-1]
    (t2, p2) = sys.pressure_history[end]
    @info "压力变化率计算: $(t1) ~ $(t2)"
    dt = second(t2) - second(t1)
    dp = p2 - p1                # 压力差（Bar）
    
    return dt > 0 ? (p2, dp / dt) : (p2, 0.0)
end

"""
获取符合条件的可启动压缩机列表（按优先级排序）
"""
function get_available_compressors(sys::AirCompressorSystem)::Vector{Compressor}
    available = Compressor[]
    for comp in sys.compressors
        # 筛选条件：远程控制模式、无故障、停机状态、满足停机保护时间
        if comp.mode == REMOTE_CONTROL && 
           isnothing(comp.fault_code) && 
           comp.state == STOPPED && 
           now() - comp.last_stop_time > Second(Int(sys.params.comp_stop_protect))
            push!(available, comp)
        end
    end
    # 按系统配置的优先级排序
    sort!(available, by=c -> findfirst(==(c.id), sys.params.comp_priority))
    return available
end

"""
获取符合条件的可卸载压缩机列表（按优先级排序，优先级低的先卸载）
"""
function get_unloadable_compressors(sys::AirCompressorSystem)::Vector{Compressor}
    unloadable = Compressor[]
    for comp in sys.compressors
        # 筛选条件：远程控制模式、无故障、自动调节状态
        if comp.mode == REMOTE_CONTROL && 
           isnothing(comp.fault_code) && 
           comp.state == AUTO_REGULATED
            push!(unloadable, comp)
        end
    end
    # 按系统配置的优先级逆序排序（优先级低的先卸载）
    sort!(unloadable, by=c -> findfirst(==(c.id), sys.params.comp_priority), rev=true)
    return unloadable
end

"""
检查压力报警并记录
"""
function check_pressure_alarm!(sys::AirCompressorSystem, current_p::Float64)
    if current_p <= sys.params.p_low_alarm && 
       (isempty(sys.alarms) || !occursin("压力低限报警", last(sys.alarms)[2]))
        push!(sys.alarms, (now(), "压力低限报警: $(current_p) Bar <= $(sys.params.p_low_alarm) Bar"))
        @error "压力低限报警: $(current_p) Bar"
    elseif current_p >= sys.params.p_high_alarm && 
           (isempty(sys.alarms) || !occursin("压力高限报警", last(sys.alarms)[2]))
        push!(sys.alarms, (now(), "压力高限报警: $(current_p) Bar >= $(sys.params.p_high_alarm) Bar"))
        @error "压力高限报警: $(current_p) Bar"
    end
end

"""
超低压处理逻辑（p <= p_low_alarm）
"""
function handle_ultra_low_pressure!(sys::AirCompressorSystem)
    @warn "进入超低压处理模式"
    available = get_available_compressors(sys)
    
    if !isempty(available)
        # 立即启动优先级最高的可用压缩机
        comp = available[1]
        success, msg = remote_start_compressor(sys, comp.id)
        @info "超低压启动压缩机: $msg"
        
        # 启动后立即切换到自动调节状态
        if success
            remote_auto_regulate_compressor(sys, comp.id)
        end
        
        # 设置超低压启动间隔标志
        sys.new_start_flag = true
    else
        push!(sys.alarms, (now(), "超低压但无可用压缩机启动"))
        sys.emergency_flag = true  # 进入应急状态
        @error "超低压但无可用压缩机启动"
    end
end

"""
低压处理逻辑（p_low_alarm < p <= p_low）
"""
function handle_low_pressure!(sys::AirCompressorSystem, current_p::Float64, dp_dt::Float64)
    @info "进入低压处理模式"
    available = get_available_compressors(sys)
    
    # 压力持续下降且速率超过阈值，需要加机
    if dp_dt <= -sys.params.delta_p_drop && !isempty(available)
        # 检查是否满足加机延时
        if !sys.new_start_flag || (now() - last(sys.pressure_history)[1] > Second(Int(sys.params.add_delay)))
            comp = available[1]
            success, msg = remote_start_compressor(sys, comp.id)
            @info "低压加机: $msg"
            
            if success
                remote_auto_regulate_compressor(sys, comp.id)
                sys.new_start_flag = true
            end
        end
    elseif dp_dt >= 0  # 压力稳定或上升，重置标志
        sys.new_start_flag = false
    end
end

"""
超高压处理逻辑（p >= p_high_alarm）
"""
function handle_ultra_high_pressure!(sys::AirCompressorSystem)
    @warn "进入超高压处理模式"
    unloadable = get_unloadable_compressors(sys)
    
    if !isempty(unloadable)
        # 立即卸载优先级最低的运行中压缩机
        comp = unloadable[1]
        success, msg = remote_manual_unload_compressor(sys, comp.id)
        @info "超高压卸载压缩机: $msg"
        
        # 卸载后延迟一段时间停机
        if success
            schedule_stop_after_delay(sys, comp.id, sys.params.ultra_high_delay)
            sys.new_unload_flag = true
        end
    else
        push!(sys.alarms, (now(), "超高压但无可用压缩机卸载"))
        sys.emergency_flag = true  # 进入应急状态
        @error "超高压但无可用压缩机卸载"
    end
end

"""
高压处理逻辑（p_high <= p < p_high_alarm）
"""
function handle_high_pressure!(sys::AirCompressorSystem, current_p::Float64, dp_dt::Float64)
    @info "进入高压处理模式"
    unloadable = get_unloadable_compressors(sys)
    
    # 压力持续上升且速率超过阈值，需要减机
    if dp_dt >= sys.params.delta_p_rise && !isempty(unloadable)
        # 检查是否满足减机延时
        if !sys.new_unload_flag || (now() - last(sys.pressure_history)[1] > Second(Int(sys.params.remove_delay)))
            comp = unloadable[1]
            success, msg = remote_manual_unload_compressor(sys, comp.id)
            @info "高压减机: $msg"
            
            if success
                # 卸载后根据时间判断是否停机
                schedule_stop_after_delay(sys, comp.id, sys.params.comp_unload_to_stop)
                sys.new_unload_flag = true
            end
        end
    elseif dp_dt <= 0  # 压力稳定或下降，重置标志
        sys.new_unload_flag = false
    end
end

"""
压力稳定区处理逻辑（p_low < p < p_high）
"""
function maintain_stable_pressure!(sys::AirCompressorSystem)
    @info "进入压力稳定区维护模式"
    
    # 重置应急标志
    if sys.emergency_flag
        sys.emergency_flag = false
        push!(sys.alarms, (now(), "压力恢复正常，退出应急状态"))
        @info "压力恢复正常，退出应急状态"
    end
    
    # 检查是否需要均衡负载（根据运行时间）
    if sys.params.comp_balance_load
        balance_compressor_load!(sys)
    end
end

"""
均衡压缩机负载（根据运行时间切换，避免某台设备过度使用）
"""
function balance_compressor_load!(sys::AirCompressorSystem)
    running = [c for c in sys.compressors if c.state == AUTO_REGULATED]
    stopped = get_available_compressors(sys)
    
    if length(running) > 0 && length(stopped) > 0
        # 找出运行时间最长的和最短的
        max_run_comp = argmax(c.run_time for c in running)
        min_run_comp = stopped[argmin(c.run_time for c in stopped)]
        
        # 如果差值超过阈值，进行切换（阈值设为1小时=3600秒）
        if max_run_comp.run_time - min_run_comp.run_time > 3600
            @info "均衡负载: 卸载运行最久的压缩机 $(max_run_comp.id)（运行时间: $(max_run_comp.run_time)秒）, 启动运行最短的压缩机 $(min_run_comp.id)（运行时间: $(min_run_comp.run_time)秒）"
            
            # 先卸载运行最久的
            success, unload_msg = remote_manual_unload_compressor(sys, max_run_comp.id)
            if success
                schedule_stop_after_delay(sys, max_run_comp.id, sys.params.comp_unload_to_stop)
                
                # 再启动运行最短的
                success, start_msg = remote_start_compressor(sys, min_run_comp.id)
                if success
                    remote_auto_regulate_compressor(sys, min_run_comp.id)
                end
            end
        end
    end
end

"""
应急状态处理
"""
function handle_emergency_state!(sys::AirCompressorSystem, current_p::Float64)
    @error "系统处于应急状态"
    
    # 检查压力是否恢复正常
    if current_p > sys.params.p_low_alarm && current_p < sys.params.p_high_alarm
        sys.emergency_flag = false
        push!(sys.alarms, (now(), "压力恢复正常，退出应急状态"))
        @info "压力恢复正常，退出应急状态"
        return
    end
    
    # 应急状态下的极端处理
    if current_p <= sys.params.p_low_alarm
        # 尝试启动所有可能的压缩机
        for comp in get_available_compressors(sys)
            success, _ = remote_start_compressor(sys, comp.id)
            if success
                remote_auto_regulate_compressor(sys, comp.id)
            end
        end
    elseif current_p >= sys.params.p_high_alarm
        # 尝试卸载所有可能的压缩机
        for comp in get_unloadable_compressors(sys)
            success, _ = remote_manual_unload_compressor(sys, comp.id)
            if success
                schedule_stop_after_delay(sys, comp.id, 10.0)  # 应急情况下快速停机
            end
        end
    end
end

"""
延时后停机压缩机（异步执行）
"""
function schedule_stop_after_delay(sys::AirCompressorSystem, comp_id::Int, delay_seconds::Float64)
    @async begin
        sleep(delay_seconds)
        comp = get_compressor(sys, comp_id)
        if !isnothing(comp) && comp.state == MANUAL_UNLOADED
            success, msg = remote_stop_compressor(sys, comp_id)
            @info "延时停机: $msg"
        end
    end
end

"""
更新设备运行时间
"""
function update_equipment_runtime!(sys::AirCompressorSystem)
    # 更新压缩机运行时间（假设每秒更新一次）
    for comp in sys.compressors
        if comp.state in [MANUAL_UNLOADED, AUTO_REGULATED]
            comp.run_time += 1.0
            if comp.state == AUTO_REGULATED
                comp.load_time += 1.0  # 自动调节状态才算加载时间
            end
        end
    end
end

"""
获取压缩机（辅助函数）
"""
function get_compressor(sys::AirCompressorSystem, comp_id::Int)::Union{Compressor, Nothing}
    for comp in sys.compressors
        if comp.id == comp_id
            return comp
        end
    end
    return nothing
end

"""
压缩机远程控制辅助函数（假设已实现）
"""
function remote_start_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    # 实现细节与前面相同
    comp = get_compressor(sys, comp_id)
    isnothing(comp) && return (false, "压缩机ID=$comp_id不存在")
    
    # 实际应用中这里会发送控制指令到硬件
    comp.state = MANUAL_UNLOADED
    return (true, "压缩机ID=$comp_id启动成功")
end

function remote_auto_regulate_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    isnothing(comp) && return (false, "压缩机ID=$comp_id不存在")
    
    comp.state = AUTO_REGULATED
    return (true, "压缩机ID=$comp_id切换为自动调节")
end

function remote_manual_unload_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    isnothing(comp) && return (false, "压缩机ID=$comp_id不存在")
    
    comp.state = MANUAL_UNLOADED
    return (true, "压缩机ID=$comp_id已卸载")
end

function remote_stop_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    isnothing(comp) && return (false, "压缩机ID=$comp_id不存在")
    
    comp.state = STOPPED
    comp.last_stop_time = now()
    return (true, "压缩机ID=$comp_id已停机")
end

"""
压缩机联锁主逻辑（定时调用，如每1秒执行一次）
"""
function compressor_interlock_logic(sys::AirCompressorSystem)
    # 仅在自动联锁模式下执行
    if sys.mode != AUTO_INTERLOCK
        @info "系统处于非自动联锁模式，不执行联锁逻辑"
        return
    end
    
    # 1. 更新总管压力历史（用于趋势判断）
    push!(sys.pressure_history, (now(), sys.main_pressure))
    update_pressure_history!(sys)
    
    # 2. 计算当前压力和变化趋势
    current_p, dp_dt = calculate_pressure_trend(sys)
    @info "当前压力: $(round(current_p, digits=2)) Bar, 变化率: $(round(dp_dt, digits=4)) Bar/s"
    
    # 3. 检查压力报警状态
    check_pressure_alarm!(sys, current_p)
    
    # 4. 根据压力状态执行相应逻辑
    if sys.emergency_flag
        handle_emergency_state!(sys, current_p)
    else
        # 正常状态下的压力控制逻辑
        if current_p <= sys.params.p_low_alarm
            handle_ultra_low_pressure!(sys)  # 超低压处理
        elseif current_p <= sys.params.p_low
            handle_low_pressure!(sys, current_p, dp_dt)  # 低压处理
        elseif current_p >= sys.params.p_high_alarm
            handle_ultra_high_pressure!(sys)  # 超高压处理
        elseif current_p >= sys.params.p_high
            handle_high_pressure!(sys, current_p, dp_dt)  # 高压处理
        else
            maintain_stable_pressure!(sys)  # 压力稳定区处理
        end
    end
    
    # 5. 更新设备运行时间
    update_equipment_runtime!(sys)
end

"""
基于当前系统状态生成优化建议
"""
function generate_system_optimization_suggestion(sys::AirCompressorSystem)::Dict{String, Any}
    # 获取当前压力状态
    current_p = sys.main_pressure
    running_compressors = [c for c in sys.compressors if c.state == RUNNING]
    running_count = length(running_compressors)
    
    # 确定建议的运行压缩机数量
    suggested_running_count = running_count
    
    if current_p < sys.params.p_low
        # 压力过低，需要增加运行的压缩机
        suggested_running_count = min(length(sys.compressors), running_count + 1)
    elseif current_p > sys.params.p_high
        # 压力过高，可以减少运行的压缩机
        suggested_running_count = max(1, running_count - 1)
    end
    
    # 生成压缩机建议
    suggested_compressors = []
    sorted_compressors = sort(sys.compressors, by=c -> c.id)
    
    for (i, comp) in enumerate(sorted_compressors)
        target_running = i <= suggested_running_count
        target_pressure = sys.params.p_set + (rand() - 0.5) * 0.2
        
        push!(suggested_compressors, Dict(
            "id" => comp.id,
            "running" => target_running,
            "pressureSetpoint" => round(target_pressure, digits=1)
        ))
    end
    
    # 生成干燥机建议（基于压缩机运行数量）
    suggested_dryers = []
    required_dryers = max(1, ceil(Int, suggested_running_count / 2))
    
    for (i, dryer) in enumerate(sys.dryers)
        target_running = i <= required_dryers
        push!(suggested_dryers, Dict(
            "id" => dryer.id,
            "running" => target_running
        ))
    end
    
    # 系统压力设定建议
    system_pressure_suggestion = sys.params.p_set + (rand() - 0.5) * 0.1
    
    return Dict(
        "system" => Dict(
            "pressureSetpoint" => round(system_pressure_suggestion, digits=1),
            "message" => "Optimal settings based on current system state"
        ),
        "compressors" => suggested_compressors,
        "dryers" => suggested_dryers
    )
end

