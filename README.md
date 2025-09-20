# 启动说明

本项目包含前端仿真界面和后端Julia服务，以下是详细的启动说明。

## TODO

1. Julia后端的服务目前只返回建议随机值，并未真正实现智能控制，需要进一步开发完善。

## 项目结构

```
Ai4EComCtl/
├── simulator/
│   └── air_compressor_simulator.html  # 前端仿真界面
├── server.jl                          # 后端服务
├── main.jl                            # 后端启动入口
└── Project.toml                       # Julia项目依赖
```

## 前端启动

前端是一个纯静态HTML页面，有以下几种启动方式：

### 方式一：直接在浏览器中打开（推荐）
```bash
# 在文件资源管理器中找到文件并双击打开
Ai4EComCtl/simulator/air_compressor_simulator.html

# 或者在浏览器地址栏输入文件路径
file:///path/to/Ai4EComCtl/simulator/air_compressor_simulator.html
```


### 方式二：使用Live Server（VS Code插件）
如果使用VS Code，可以安装Live Server插件，右键`air_compressor_simulator.html`选择"Open with Live Server"。

## 后端启动

后端使用Julia语言编写，需要先安装Julia环境。

### 环境准备

1. 安装Julia (建议版本1.6+)
2. 安装项目依赖：
```bash
# 进入项目目录
cd Ai4EComCtl/

# 启动Julia并激活项目环境
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### 启动服务

#### 方式一：命令行启动（推荐）
```bash
# 进入项目目录
cd Ai4EComCtl/

# 启动后端服务
julia --project=. main.jl
```

#### 方式二：交互式启动
```bash
# 进入项目目录
cd Ai4EComCtl/

# 启动Julia
julia --project=.

# 在Julia REPL中执行
julia> include("main.jl")
julia> julia_main()
```

服务默认监听在 `0.0.0.0:8081`，可以通过以下地址访问：
- 本地访问: http://localhost:8081/hello
- 外部访问: http://[your-server-ip]:8081/hello

## 连接前后端

1. 启动后端服务
2. 在浏览器中打开前端页面
3. 在前端界面中找到"后端连接控制"区域
4. 确认URL为 `http://127.0.0.1:8081`（默认地址）
5. 点击"连接"按钮，显示"已连接"即表示连接成功

## 功能说明

- **手动调节模式**：用户可以手动控制空压机和干燥机的启停状态
- **智能调节模式**：系统根据后端算法建议自动调节设备运行状态
- **实时监控**：显示系统压力、流量、功率等关键参数
- **效率分析**：提供负载均衡度和能效比分析
- **趋势图表**：可视化显示系统参数变化趋势

## 注意事项

1. 前端为纯静态页面，无需特殊服务器环境
2. 后端需要Julia运行环境
3. 前后端需要网络连通才能实现完整功能
4. 首次运行后端可能需要较长时间进行预编译
5. 如需修改监听端口，可在 [server.jl](file://d:\develop\空压\Ai4EComCtl\server.jl) 文件中调整

## Docker启动

### 启动
```
# 运行容器
docker run -p 8081:8081 air-compressor-simulator
```