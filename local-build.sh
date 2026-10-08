#!/bin/bash
set -e
# ============================================================
# local-build.sh
# 本地一键编译脚本（使用 Docker，无需手动配置环境）
# 用法: bash local-build.sh [branch] [suffix]
# 示例: bash local-build.sh master -iommu
# ============================================================

PVE_BRANCH="${1:-master}"
KERNEL_SUFFIX="${2:--iommu}"
BUILD_CORES=$(nproc)

echo "============================================================"
echo " PVE IOMMU Kernel 本地编译脚本"
echo "============================================================"
echo " Branch:  $PVE_BRANCH"
echo " Suffix:  $KERNEL_SUFFIX"
echo " Cores:   $BUILD_CORES"
echo "============================================================"
echo ""

# 检查 Docker 是否安装
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装，请先安装 Docker:"
    echo "   curl -fsSL https://get.docker.com | sh"
    exit 1
fi

# 创建输出目录
mkdir -p output

# 构建 Docker 镜像
echo "==> 构建编译环境 Docker 镜像..."
docker build -t pve-kernel-builder .

# 运行编译
echo ""
echo "==> 开始编译内核..."
echo "编译可能需要 1-4 小时，请耐心等待。"
echo ""

docker run --rm \
    -v "$(pwd)/scripts:/build/scripts:ro" \
    -v "$(pwd)/output:/output" \
    -e PVE_BRANCH="$PVE_BRANCH" \
    -e KERNEL_SUFFIX="$KERNEL_SUFFIX" \
    -e APPLY_ACS=true \
    -e BUILD_CORES="$BUILD_CORES" \
    pve-kernel-builder

echo ""
echo "============================================================"
echo " ✅ 编译完成！产物在 output/ 目录下："
echo "============================================================"
ls -lh output/
