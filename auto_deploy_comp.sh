#!/bin/bash
# 定义变量
IMAGE_NAME="registry.cn-hangzhou.aliyuncs.com/ai4energy/air_compressor_simulator:1.0"
CONTAINER_NAME="air_compressor_simulator"

# 停止并删除旧容器（如果存在）
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "旧容器已存在，正在停止并删除..."
  docker stop $CONTAINER_NAME
  docker rm $CONTAINER_NAME
fi

# 删除旧镜像（如果存在）
if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_NAME}$"; then
  echo "旧镜像已存在，正在删除..."
  docker rmi -f $IMAGE_NAME
fi

# 交互式输入阿里云密码
echo -n "请输入阿里云镜像仓库密码: "
read -s pw
echo  # 换行

# 拉取最新镜像
echo "登录阿里云镜像仓库"
docker login --username=yjyjake123 --password=$pw registry.cn-hangzhou.aliyuncs.com
echo "拉取最新镜像: $IMAGE_NAME"
docker pull $IMAGE_NAME

# 启动新容器（根据实际需求调整参数）
echo "启动新容器"
docker run -d --name $CONTAINER_NAME \
  -p 8081:8081 \
  --restart=always \
  $IMAGE_NAME

sleep 5

docker container logs air_compressor_simulator