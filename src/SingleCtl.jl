"""
远程启动压缩机
- 输入：系统实例、压缩机ID
- 输出：是否执行成功、提示信息
"""
function remote_start_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    if isnothing(comp)
        return (false, "压缩机ID=$comp_id不存在")
    end
    # 校验启动条件
    conditions = [
        (comp.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(comp.fault_code), "设备存在故障（故障码：$(comp.fault_code)）"),
        (comp.state == STOPPED, "设备未处于停机状态（当前：$(comp.state)）"),
        (now() - comp.last_stop_time > Second(Int(sys.params.comp_stop_protect)), 
         "未满足停机保护时间（需>$(sys.params.comp_stop_protect)秒）")
    ]
    # 检查条件是否全部满足
    for (ok, msg) in conditions
        if !ok
            return (false, "启动失败：$msg")
        end
    end
    # 执行启动逻辑
    comp.state = MANUAL_UNLOADED  # 启动后先进入手动卸载状态
    comp.last_stop_time = now()  # 更新停机时间（后续运行计时用）
    push!(sys.alarms, (now(), "压缩机ID=$comp_id 远程启动成功"))
    return (true, "启动成功")
end

"""
远程自动调节压缩机（从手动卸载→自动调节）
"""
function remote_auto_regulate_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    if isnothing(comp)
        return (false, "压缩机ID=$comp_id不存在")
    end
    conditions = [
        (comp.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(comp.fault_code), "设备存在故障"),
        (comp.state == MANUAL_UNLOADED, "未处于手动卸载状态（当前：$(comp.state)）")
    ]
    for (ok, msg) in conditions
        if !ok
            return (false, "调节失败：$msg")
        end
    end
    comp.state = AUTO_REGULATED
    push!(sys.alarms, (now(), "压缩机ID=$comp_id 切换为自动调节状态"))
    return (true, "调节成功")
end

"""
远程手动卸载压缩机（从自动调节→手动卸载）
"""
function remote_manual_unload_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    if isnothing(comp)
        return (false, "压缩机ID=$comp_id不存在")
    end
    conditions = [
        (comp.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(comp.fault_code), "设备存在故障"),
        (comp.state == AUTO_REGULATED, "未处于自动调节状态（当前：$(comp.state)）")
    ]
    for (ok, msg) in conditions
        if !ok
            return (false, "卸载失败：$msg")
        end
    end
    comp.state = MANUAL_UNLOADED
    push!(sys.alarms, (now(), "压缩机ID=$comp_id 切换为手动卸载状态"))
    return (true, "卸载成功")
end

"""
远程停机压缩机（从手动卸载→停机）
"""
function remote_stop_compressor(sys::AirCompressorSystem, comp_id::Int)::Tuple{Bool, String}
    comp = get_compressor(sys, comp_id)
    if isnothing(comp)
        return (false, "压缩机ID=$comp_id不存在")
    end
    conditions = [
        (comp.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(comp.fault_code), "设备存在故障"),
        (comp.state == MANUAL_UNLOADED, "未处于手动卸载状态（当前：$(comp.state)）")
    ]
    for (ok, msg) in conditions
        if !ok
            return (false, "停机失败：$msg")
        end
    end
    comp.state = STOPPED
    comp.last_stop_time = now()
    push!(sys.alarms, (now(), "压缩机ID=$comp_id 远程停机成功"))
    return (true, "停机成功")
end

"""
远程启动干燥机
"""
function remote_start_dryer(sys::AirCompressorSystem, dryer_id::Int)::Tuple{Bool, String}
    dryer = get_dryer(sys, dryer_id)
    if isnothing(dryer)
        return (false, "干燥机ID=$dryer_id不存在")
    end
    conditions = [
        (dryer.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(dryer.fault_code), "设备存在故障"),
        (dryer.state == STOPPED, "未处于停机状态（当前：$(dryer.state)）")
    ]
    for (ok, msg) in conditions
        if !ok
            return (false, "启动失败：$msg")
        end
    end
    dryer.state = RUNNING
    push!(sys.alarms, (now(), "干燥机ID=$dryer_id 远程启动成功"))
    return (true, "启动成功")
end

"""
远程停机干燥机
"""
function remote_stop_dryer(sys::AirCompressorSystem, dryer_id::Int)::Tuple{Bool, String}
    dryer = get_dryer(sys, dryer_id)
    if isnothing(dryer)
        return (false, "干燥机ID=$dryer_id不存在")
    end
    conditions = [
        (dryer.mode == REMOTE_CONTROL, "非通讯远控模式"),
        (isnothing(dryer.fault_code), "设备存在故障"),
        (dryer.state == RUNNING, "未处于运行状态（当前：$(dryer.state)）")
    ]
    for (ok, msg) in conditions
        if !ok
            return (false, "停机失败：$msg")
        end
    end
    dryer.state = STOPPED
    dryer.last_stop_time = now()
    push!(sys.alarms, (now(), "干燥机ID=$dryer_id 远程停机成功"))
    return (true, "停机成功")
end

# 辅助函数：根据ID获取压缩机（不存在返回Nothing）
function get_compressor(sys::AirCompressorSystem, comp_id::Int)::Union{Compressor, Nothing}
    for comp in sys.compressors
        if comp.id == comp_id
            return comp
        end
    end
    return nothing
end

# 辅助函数：根据ID获取干燥机（不存在返回Nothing）
function get_dryer(sys::AirCompressorSystem, dryer_id::Int)::Union{Dryer, Nothing}
    for dryer in sys.dryers
        if dryer.id == dryer_id
            return dryer
        end
    end
    return nothing
end