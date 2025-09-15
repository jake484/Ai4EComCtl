# server.jl
using Oxygen, HTTP, JSON3, Dates
using Ai4EComCtl

# 初始化增强型空压机系统
system = EnhancedAirSystem()

# 初始化系统参数
system.core.main_pressure = 7.5
system.core.params.p_set = 7.5
system.core.params.p_low = 6.5
system.core.params.p_high = 8.5
system.core.params.p_low_alarm = 5.5
system.core.params.p_high_alarm = 9.5

# 初始化6台压缩机
for i in 1:6
    comp = Compressor(id=i)
    comp.mode = REMOTE_CONTROL
    comp.state = i <= 2 ? RUNNING : STOPPED  # 前两台运行，其余停机
    comp.outlet_pressure = i <= 2 ? 7.8 : 0.0
    push!(system.core.compressors, comp)
end

# 初始化6台干燥机
for i in 1:6
    dryer = Dryer(id=i)
    dryer.mode = REMOTE_CONTROL
    dryer.state = i <= 2 ? RUNNING : STOPPED  # 前两台运行，其余停机
    push!(system.core.dryers, dryer)
end

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

function julia_main(async=true)
    # 处理 /hello 端点
    @get "/hello" function (req)
        response = Dict(
            "code" => 200,
            "message" => "Connected to Ai4EComCtl backend"
        )
        return response
    end

    # 处理 /optimize 端点 - 核心优化逻辑
    @post "/optimize" function (req)
        try
            # 解析请求数据
            body_data = JSON3.read(req.body)

            # 更新系统状态
            if haskey(body_data, :systemPressure)
                system.core.main_pressure = Float64(body_data.systemPressure)
            end

            # 更新压缩机状态
            if haskey(body_data, :compressors)
                for comp_data in body_data.compressors
                    comp_id = comp_data.id
                    comp = get_compressor(system.core, comp_id)
                    if comp !== nothing
                        comp.state = comp_data.running ? RUNNING : STOPPED
                        comp.outlet_pressure = get(comp_data, :dischargePressure, 0.0)
                        # 更新运行时间
                        if comp_data.running
                            comp.run_time += 10.0
                            comp.load_time += 10.0
                        end
                    end
                end
            end

            # 更新干燥机状态
            if haskey(body_data, :dryers)
                for dryer_data in body_data.dryers
                    dryer_id = dryer_data.id
                    dryer = get_dryer(system.core, dryer_id)
                    if dryer !== nothing
                        dryer.state = dryer_data.running ? RUNNING : STOPPED
                        # 更新运行时间
                        if dryer_data.running
                            dryer.run_time += 10.0
                        end
                    end
                end
            end

            # 执行压缩机联锁逻辑计算
            compressor_interlock_logic(system.core)

            # 生成优化建议
            optimization_result = generate_system_optimization_suggestion(system.core)

            response = Dict(
                "code" => 200,
                "message" => "Optimization completed",
                "data" => optimization_result
            )

            return response
        catch e
            @error "Optimization error" exception = (e, catch_backtrace())
            response = Dict(
                "code" => 500,
                "message" => "Internal server error: $(sprint(showerror, e))",
                "data" => nothing
            )
            return response
        end
    end

    @info "正在启动服务器......"
    # 本地测试 async=true，服务器上 async=false。异步测试便于调试
    serve(host="0.0.0.0", port=8081, async=async, middleware=[CorsMiddleware])

    @info "服务器启动成功！"
    return 0
end

julia_main()