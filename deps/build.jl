# 输出构建开始信息
using Logging
@info "构建过程日志将记录到 build.log"
try  
    # 构建成功的最终信息
    @info "构建成功!"
catch e
    # 捕获并输出错误信息
    @error "构建失败: " exception=(e,catch_backtrace())
    # 以非零状态码退出，表明构建失败
    exit(1)
end
    