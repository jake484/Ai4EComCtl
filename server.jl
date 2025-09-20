# server-new.jl
using Oxygen, HTTP, JSON3, Dates
using Ai4EComCtl

# 先初始化压缩机和干燥机列表
const compressors = Compressor[]
const dryers = Dryer[]

# 初始化6台压缩机
for i in 1:6
    comp = Compressor(id=i)
    comp.mode = REMOTE_CONTROL
    comp.state = i <= 2 ? RUNNING : STOPPED  # 前两台运行，其余停机
    comp.outlet_pressure = i <= 2 ? 7.8 : 0.0
    push!(compressors, comp)
end

# 初始化6台干燥机
for i in 1:6
    dryer = Dryer(id=i)
    dryer.mode = REMOTE_CONTROL
    dryer.state = i <= 2 ? RUNNING : STOPPED  # 前两台运行，其余停机
    push!(dryers, dryer)
end

# 现在初始化空压机系统，SystemParams会根据compressors和dryers的数量自动设置参数
system = AirCompressorSystem(;
    compressors=compressors,
    dryers=dryers,
    mode=AUTO_INTERLOCK
)

# # 初始化系统参数
# system.main_pressure = 7.5
# system.params.p_set = 7.5
# system.params.p_low = 7.3
# system.params.p_high = 7.7
# system.params.p_low_alarm = 5.5
# system.params.p_high_alarm = 9.5

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
    # 在 julia_main() 函数中添加以下代码块
    @get "/" function (req)
        # 指定HTML文件路径
        html_file_path = joinpath(@__DIR__, "simulator", "air_compressor_simulator.html")
        # 读取HTML文件内容
        return file(html_file_path)
    end

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
                system.main_pressure = Float64(body_data.systemPressure)
            end

            # 根据前端传来的系统压力设定值更新系统参数
            if haskey(body_data, :systemPressureSetpoint)
                p_set = Float64(body_data.systemPressureSetpoint)
                system.params.p_set = p_set
                system.params.p_low = p_set - 0.3
                system.params.p_high = p_set + 0.3
                system.params.p_low_alarm = p_set - 0.5
                system.params.p_high_alarm = p_set + 0.5
            end

            # 更新压缩机状态
            if haskey(body_data, :compressors)
                for comp_data in body_data.compressors
                    comp_id = comp_data.id
                    comp = get_compressor(system, comp_id)
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
                    dryer = get_dryer(system, dryer_id)
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
            compressor_interlock_logic(system)

            # 生成优化建议
            optimization_result = generate_system_optimization_suggestion(system)

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