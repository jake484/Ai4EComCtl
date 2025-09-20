# 使用 Julia 官方镜像作为基础镜像
FROM julia:1.11

# 设置工作目录
WORKDIR /app

# 复制项目文件
COPY . .

# 安装 Julia 依赖包
RUN julia -e 'using Pkg; Pkg.instantiate()'
RUN julia main.jl

# 暴露端口 8081
EXPOSE 8081

# 启动命令
CMD ["julia", "--project=@.", "main.jl", "true"]