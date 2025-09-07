# server.jl
using Oxygen, HTTP, Dates
import JSON

# 跨域请求头
const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Headers" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS"
]


"""
    CorsMiddleware(handler)

创建一个CORS中间件，用于处理跨域请求。

# 参数
- `handler`: 一个处理请求的函数，用于执行实际的请求处理逻辑。

# 返回值
返回一个闭包函数，该闭包函数将处理HTTP请求，并在特定条件下添加CORS头。
"""
function CorsMiddleware(handler)
    return function (req::HTTP.Request)
        # println("CORS middleware")
        # determine if this is a pre-flight request from the browser
        if HTTP.method(req) ∈ ["POST", "GET", "OPTIONS"]
            return HTTP.Response(200, CORS_HEADERS, HTTP.body(handler(req)))
        else
            return handler(req) # passes the request to the AuthMiddleware
        end
    end
end

"""
生成空压机系统的优化建议（模拟数据）
"""
function generateCompressorSuggestions(system_data)
    # 解析前端传入的数据
    air_consumption = system_data["airConsumption"]
    system_pressure = system_data["systemPressure"]
    pipe_volume = get(system_data, "pipeVolume", 200)
    
    # 计算所需总气量（增加10%余量）
    required_air = air_consumption * 1.1
    
    # 模拟空压机数据
    compressors_data = get(system_data, "compressors", [])
    num_compressors = length(compressors_data)
    
    # 初始化建议值
    suggestions = Dict(
        "system" => Dict(
            "pressureSetpoint" => round(system_pressure + (rand() * 0.6 - 0.3), digits=1),
            "timestamp" => string(now()),
            "message" => "Optimal settings calculated based on current load"
        ),
        "compressors" => [],
        "dryers" => []
    )
    
    # 计算总容量
    total_capacity = 0.0
    
    # 按效率和容量排序空压机（模拟）
    sorted_compressors = sort(compressors_data, by=c -> c["maxOutput"] * 0.7 + get(c, "efficiency", 3.0) * 0.3, rev=true)
    
    # 为每个空压机生成建议值
    for (index, comp) in enumerate(sorted_compressors)
        should_run = false
        
        # 决定是否建议运行（基于所需气量）
        if total_capacity < required_air
            should_run = true
            total_capacity += comp["maxOutput"]
        else
            # 气量足够，15%概率作为备用开启
            should_run = rand() < 0.15
        end
        
        # 基于当前压力和负载生成建议压力值
        base_pressure = get(comp, "pressureSetpoint", 7.5)
        load_factor = get(comp, "running", false) ? get(comp, "vaneOpening", 0) / 100 : 0
        
        # 负载低的空压机提高压力，负载高的降低压力
        adjustment = (0.5 - load_factor) * 0.6
        
        # 添加随机因素
        random_adjustment = (rand() * 0.4 - 0.2)
        
        suggested_pressure = base_pressure + adjustment + random_adjustment
        suggested_pressure = max(6.0, min(9.0, suggested_pressure))
        
        # 添加到建议数据结构
        push!(suggestions["compressors"], Dict(
            "id" => comp["id"],
            "running" => should_run,
            "pressureSetpoint" => round(suggested_pressure, digits=1),
            "efficiencyScore" => round(rand() * 30 + 70, digits=1), # 效率评分
            "priority" => index # 运行优先级
        ))
    end
    
    # 干燥机建议值（基于用气量）
    required_dryers = max(1, min(6, ceil(Int, air_consumption / 30)))
    dryers_data = get(system_data, "dryers", [])
    
    for (index, dryer) in enumerate(dryers_data)
        # 随机选择足够数量的干燥机运行
        should_run = index <= required_dryers ? (rand() > 0.2) : (rand() < 0.1)
        
        push!(suggestions["dryers"], Dict(
            "id" => dryer["id"],
            "running" => should_run
        ))
    end
    
    return suggestions
end

"""
优化函数（模拟实现）
"""
function optimize()
    # 模拟优化过程
    sleep(0.5) # 模拟计算时间
    
    # 返回模拟的成功结果
    return Dict(
        "status" => "SUCCESS",
        "message" => "Optimization completed successfully",
        "data" => Dict(
            "system" => Dict(
                "pressureSetpoint" => 7.8,
                "timestamp" => string(now()),
                "message" => "Optimal settings calculated"
            )
        )
    )
end

function julia_main(async=true)
    # 后端服务相应路由，接受前端传入的参数，调用优化总函数，返回优化求解结果。
    @post "/optimize" function (req)
        try
            # this will convert the request body into a Julia Dict
            paras = JSON.parse(String(req.body))
            @show paras
            
            # 生成模拟的优化建议
            suggestions = generateCompressorSuggestions(paras)
            
            # 返回数据，匹配前端request要求的格式
            return Dict(
                "code" => 200,
                "message" => "success",
                "data" => suggestions
            )
        catch e
            @error "处理优化请求时出错" exception=(e, catch_backtrace())
            return Dict(
                "code" => 500,
                "message" => "error",
                "data" => "处理请求时发生错误: " * string(e)
            )
        end
    end
    
    # 测试路由，返回hello world
    @get "/hello" function (req)
        return Dict(
            "code" => 200,
            "message" => "success",
            "data" => "hello world"
        )
    end

    @info "正在预编译......"
    # 开启服务前，先执行一次，等价于预编译
    begin
        optimize()
    end
    @info "正在启动服务器......"
    # 本地测试 async=true，服务器上 async=false。异步测试便于调试
    serve(host="0.0.0.0", port=8081, async=async, middleware=[CorsMiddleware])

    @info "服务器启动成功！"
    return 0
end