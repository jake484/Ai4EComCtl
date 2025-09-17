Base.@kwdef mutable struct SystemParams
    # 压力参数（单位：Bar）
    p_low_alarm::Float64 = 5.9          # (1) 压力低限报警值
    p_low::Float64 = 6.2                # (2) 压力低限设定值
    p_set::Float64 = 6.6                # (3) 压力设定值
    p_high::Float64 = 6.9               # (4) 压力高限设定值
    p_high_alarm::Float64 = 7.2         # (5) 压力高限报警值
    delta_p_drop::Float64 = 0.06        # (6) 压力下降临界值（默认0.06 Bar/S）
    delta_p_rise::Float64 = 0.06        # (7) 压力上升临界值（默认0.06 Bar/S）

    # 时间参数（单位：秒）
    pressure_delay::Float64 = 5.0           # (8) 压力判断延时
    comp_load_interval::Float64 = 10.0      # (9) 压缩机加载时间间隔
    comp_unload_interval::Float64 = 10.0    # (10) 压缩机卸载时间间隔
    comp_start_interval::Float64 = 30.0     # (11) 压缩机启动时间间隔
    comp_stop_protect::Float64 = 300.0      # (12) 压缩机停机保护时间
    comp_unload_to_stop::Float64 = 600.0    # (13) 压缩机卸载到停机延时

    # 压缩机优先级与联锁配置
    comp_screw_priority::Bool = true        # (14) 螺杆机优先
    comp_balance_load::Bool = true          # (15) 时间均衡负载
    comp_priority::Vector{Int} = [1, 2, 3, 4, 5]  # (16) 压缩机优先级序列
    comp_interlock::Vector{Bool} = [true, true, true, true, true]  # (17) 压缩机参与联锁

    # 干燥机参数
    dryer_balance_load::Bool = true     # (18) 干燥机时间均衡负载
    dryer_priority::Vector{Int} = [1, 2, 3, 4]   # (19) 干燥机优先级序列
    dryer_interlock::Vector{Bool} = [true, true, true, true]  # (20) 干燥机参与联锁

    # 场景化参数（多台变频/工频+变频）
    var_load_threshold::Float64 = 90.0      # 变频机加载阈值
    var_unload_threshold::Float64 = 50.0    # 变频机卸载阈值
    add_delay::Float64 = 30.0               # 加机延时
    remove_delay::Float64 = 120.0           # 减机延时
    ultra_low_delay::Float64 = 15.0         # 超低压启动间隔
    ultra_high_delay::Float64 = 2.0         # 超高压保护延时
end


Base.@kwdef mutable struct Compressor
    id::Int                       # 设备ID
    mode::ControlMode = REMOTE_CONTROL    # 控制模式
    state::State = STOPPED     # 运行状态
    last_stop_time::DateTime = now() - Second(3600)  # 上次停机时间
    run_time::Float64 = 0.0             # 累计运行时间（秒）
    load_time::Float64 = 0.0            # 累计加载时间（秒）
    outlet_pressure::Float64 = 0.0      # 出口压力（Bar）
    fault_code::Union{Int,Nothing} = nothing  # 故障码（无故障为Nothing）
    target_pressure::Float64 = 0.0      # 目标压力设定值（Bar）
end
Base.@kwdef mutable struct Dryer
    id::Int                       # 设备ID（1~4）
    mode::ControlMode = REMOTE_CONTROL    # 控制模式
    state::State = STOPPED          # 运行状态
    last_stop_time::DateTime = now() - Second(3600)  # 上次停机时间
    run_time::Float64 = 0.0             # 累计运行时间（秒）
    fault_code::Union{Int,Nothing} = nothing  # 故障码（无故障为Nothing）
end

Base.@kwdef mutable struct AirCompressorSystem
    mode::SystemMode = AUTO_INTERLOCK              # 系统控制模式
    compressors::Vector{Compressor} = Compressor[] # 压缩机列表
    dryers::Vector{Dryer} = Dryer[]               # 干燥机列表
    params::SystemParams = SystemParams(
        comp_priority=collect(1:length(compressors)),
        dryer_priority=collect(1:length(dryers)),
        comp_interlock=trues(length(compressors)),
        dryer_interlock=trues(length(dryers))
    )          # 系统参数配置
    main_pressure::Float64 = 0.0                  # 总管压力（Bar）
    pressure_history::Vector{Tuple{DateTime,Float64}} = Tuple{DateTime,Float64}[] # 压力历史（时间+值）
    # 标志位
    emergency_flag::Bool = false                  # 应急处理状态
    new_start_flag::Bool = false                  # 新启动标志
    new_load_flag::Bool = false                   # 新加载标志
    new_unload_flag::Bool = false                 # 新卸载标志
    # 报警信息
    alarms::Vector{Tuple{DateTime,String}} = Tuple{DateTime,String}[] # 报警历史（时间+信息）
end
