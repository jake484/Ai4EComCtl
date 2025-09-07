# 控制模式枚举
@enum ControlMode REMOTE_LOCAL=1 REMOTE_CONTROL=2  # 1-本地模式，2-通讯远控模式

# 压缩机运行状态枚举
@enum State STOPPED=1 MANUAL_UNLOADED=2 AUTO_REGULATED=3 RUNNING=4 FAULT=5 # 1-停机，2-手动卸载，3-自动调节，4-运行，5-故障

# 系统控制模式枚举
@enum SystemMode REMOTE_SINGLE=1 AUTO_INTERLOCK=2  # 1-远程单机模式，2-自动联锁模式