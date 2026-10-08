#!/bin/bash
set -e

# ============================================================
# build-in-docker.sh
# 在 Docker 容器内编译 PVE 内核
# ============================================================
# 环境变量：
#   PVE_BRANCH      - PVE 内核分支（默认 master）
#   KERNEL_SUFFIX   - 内核后缀（默认 -iommu）
#   APPLY_ACS       - 是否应用 ACS 补丁（默认 true）
#   BUILD_CORES     - 并行编译线程数
# ============================================================

PVE_BRANCH="${PVE_BRANCH:-master}"
KERNEL_SUFFIX="${KERNEL_SUFFIX:--iommu}"
APPLY_ACS="${APPLY_ACS:-true}"
BUILD_CORES="${BUILD_CORES:-$(nproc)}"

echo "============================================================"
echo " PVE Kernel Build Environment"
echo "============================================================"
echo " Branch:      $PVE_BRANCH"
echo " Suffix:      $KERNEL_SUFFIX"
echo " ACS Patch:   $APPLY_ACS"
echo " Cores:       $BUILD_CORES"
echo " Date:        $(date)"
echo "============================================================"
echo ""

# 确保输出目录存在
mkdir -p /output

# ============================================================
# 第一步：克隆 PVE 内核源码
# ============================================================
echo "==> [1/6] 克隆 PVE 内核源码 (branch: $PVE_BRANCH)..."

cd /build
# 使用官方 proxmox git 仓库
if [ ! -d "pve-kernel-src" ]; then
    git clone --depth=1 --branch="$PVE_BRANCH" https://git.proxmox.com/git/pve-kernel.git pve-kernel-src 2>&1 || {
        echo "深度克隆失败，尝试完整克隆..."
        git clone --branch="$PVE_BRANCH" https://git.proxmox.com/git/pve-kernel.git pve-kernel-src
    }
fi

cd pve-kernel-src
echo "源码目录内容:"
ls -la

# ============================================================
# 第二步：初始化 git submodule（Ubuntu 内核 + ZFS）
# ============================================================
echo ""
echo "==> [2/6] 初始化子模块（Ubuntu 内核源码 + ZFS）..."
echo "这一步可能需要较长时间（内核源码约 1-2GB）..."

# 配置 git 使用浅克隆子模块
git config submodule.fetchJobs 4
git submodule update --init --recursive --depth=1 2>&1 || {
    echo "浅克隆失败，尝试完整克隆子模块..."
    git submodule sync
    git submodule update --init --recursive
}

echo "子模块初始化完成:"
ls -la submodules/ 2>/dev/null || echo "无 submodules 目录"
ls -la ubuntu-* 2>/dev/null || echo "无 ubuntu-* 目录"
find . -maxdepth 3 -name "Makefile" -path "*/linux*" -o -name "Makefile" -path "*/ubuntu*" 2>/dev/null | head -10

# ============================================================
# 第三步：解析内核版本信息
# ============================================================
echo ""
echo "==> [3/6] 解析内核版本信息..."

# 从顶层 Makefile 读取版本号信息
if [ -f "Makefile" ]; then
    echo "=== Makefile 前 30 行 ==="
    head -30 Makefile
    echo ""
fi

# PVE Makefile 格式（老版本）:
#   kernel_maj = 6
#   kernel_min = 8
#   kernel_patchlevel = 12
#   krel = 1
#   pkgrel = 1
# 新版本可能不同

KERNEL_MAJ=$(grep -E "^kernel_maj\s*=" Makefile | head -1 | sed 's/.*=\s*//' | tr -d ' ')
KERNEL_MIN=$(grep -E "^kernel_min\s*=" Makefile | head -1 | sed 's/.*=\s*//' | tr -d ' ')
KERNEL_PATCH=$(grep -E "^kernel_patchlevel\s*=" Makefile | head -1 | sed 's/.*=\s*//' | tr -d ' ')
KREL=$(grep -E "^krel\s*=" Makefile | head -1 | sed 's/.*=\s*//' | tr -d ' ')
PKGREL=$(grep -E "^pkgrel\s*=" Makefile | head -1 | sed 's/.*=\s*//' | tr -d ' ')

echo "解析结果:"
echo "  kernel_maj       = $KERNEL_MAJ"
echo "  kernel_min       = $KERNEL_MIN"
echo "  kernel_patchlevel= $KERNEL_PATCH"
echo "  krel             = $KREL"
echo "  pkgrel           = $PKGREL"

# 自动识别构建方式
BUILD_METHOD="makefile"  # PVE 标准 Makefile 构建
if [ ! -f "Makefile" ] || ! grep -q "pve-kernel" Makefile 2>/dev/null; then
    echo "警告: 未找到标准 PVE Makefile，尝试其他方式..."
fi

# ============================================================
# 第四步：应用 ACS Override 补丁 + 自定义配置
# ============================================================
echo ""
echo "==> [4/6] 应用补丁和配置..."

# 应用 ACS Override 补丁
if [ "$APPLY_ACS" = "true" ]; then
    echo "应用 ACS Override 增强补丁..."
    bash /build/scripts/apply-acs-patch.sh /build/pve-kernel-src "$KERNEL_SUFFIX"
else
    echo "跳过 ACS 补丁，仅修改版本后缀..."
    # 修改 extraversion
    if [ -f "Makefile" ] && grep -q "^extraversion" Makefile; then
        sed -i "s|^\(extraversion\s*=\s*.*-pve\)\$|\1${KERNEL_SUFFIX}|" Makefile
        grep "^extraversion" Makefile
    fi
fi

# 确保内核配置开启 IOMMU/VFIO
bash /build/scripts/apply-config.sh /build/pve-kernel-src

# ============================================================
# 第五步：编译内核
# ============================================================
echo ""
echo "==> [5/6] 开始编译内核（使用 $BUILD_CORES 线程）..."
echo "编译可能需要 1-4 小时，请耐心等待..."
echo ""

export DEB_BUILD_OPTIONS="nocheck parallel=$BUILD_CORES"
export DEB_CPPFLAGS_APPEND="-Wno-error"
export CFLAGS="-Wno-error"
export KCFLAGS="-Wno-error"

# PVE 内核通常使用 make 命令构建
# Makefile 中定义了各种 target: deb, rpm, etc.
BUILD_SUCCESS=0

# 方法 1: 标准 PVE Makefile 编译
echo "--- 尝试: make deb ---"
if make -j"$BUILD_CORES" deb 2>&1 | tee /output/build.log; then
    echo "✅ make deb 成功"
    BUILD_SUCCESS=1
else
    echo "⚠️ make deb 失败，尝试 make..."
    if make -j"$BUILD_CORES" 2>&1 | tee -a /output/build.log; then
        echo "✅ make 成功"
        BUILD_SUCCESS=1
    else
        echo "⚠️ make 失败，尝试 dpkg-buildpackage..."
    fi
fi

# 方法 2: 如果 make deb 失败，手动编译 + 打包
if [ $BUILD_SUCCESS -eq 0 ]; then
    echo ""
    echo "--- 尝试: 手动构建（apt build-dep 方式）---"

    # 先尝试安装构建依赖
    apt-get update -y 2>/dev/null || true
    mk-build-deps --install --tool='apt-get -o Debug::pkgProblemResolver=yes --no-install-recommends -y' debian/control 2>/dev/null || true

    if dpkg-buildpackage -us -uc -b -j"$BUILD_CORES" 2>&1 | tee -a /output/build.log; then
        echo "✅ dpkg-buildpackage 成功"
        BUILD_SUCCESS=1
    fi
fi

# 方法 3: 直接进入内核源码子目录编译（如果 PVE Makefile 有问题）
if [ $BUILD_SUCCESS -eq 0 ]; then
    echo ""
    echo "--- 尝试: 直接编译内核源码 ---"

    KERNEL_SRC_DIR=""
    for d in submodules/ubuntu-*/ ubuntu-*/ submodules/linux-*/ linux/; do
        if [ -d "$d" ] && [ -f "$d/Makefile" ]; then
            KERNEL_SRC_DIR="$d"
            break
        fi
    done

    if [ -n "$KERNEL_SRC_DIR" ]; then
        echo "找到内核源码目录: $KERNEL_SRC_DIR"
        cd "$KERNEL_SRC_DIR"

        # 应用配置
        if [ -f "/build/pve-kernel-src/config"*".org" ]; then
            cp /build/pve-kernel-src/config*.org .config
        elif [ -f "/build/pve-kernel-src/config"* ]; then
            cp /build/pve-kernel-src/config* .config
        else
            make olddefconfig
        fi

        # 确保 IOMMU 选项开启
        scripts/config --enable VFIO \
                       --enable VFIO_IOMMU_TYPE1 \
                       --enable VFIO_PCI \
                       --enable VFIO_PCI_VGA \
                       --enable KVM \
                       --enable KVM_INTEL \
                       --enable KVM_AMD \
                       --enable PCI_IOV \
                       --enable IOMMU_API \
                       --enable INTEL_IOMMU \
                       --enable AMD_IOMMU \
                       --enable IRQ_REMAP 2>/dev/null || true

        make olddefconfig

        # 编译
        LOCALVERSION="${KERNEL_SUFFIX}" make -j"$BUILD_CORES" bindeb-pkg 2>&1 | tee -a /output/build.log
        cd /build/pve-kernel-src
        BUILD_SUCCESS=1
    fi
fi

# ============================================================
# 第六步：收集编译产物
# ============================================================
echo ""
echo "==> [6/6] 收集编译产物..."

# 收集所有 .deb 包
DEB_FILES=""

# 从当前目录和上级目录查找
for dir in /build/pve-kernel-src /build/pve-kernel-src/.. /build; do
    if [ -d "$dir" ]; then
        for f in "$dir"/*.deb; do
            if [ -f "$f" ]; then
                echo "  找到: $(basename "$f")"
                cp "$f" /output/
                DEB_FILES="$DEB_FILES $f"
            fi
        done
    fi
done

# 递归查找
find /build -maxdepth 4 -name "*.deb" -type f 2>/dev/null | while read -r f; do
    bname=$(basename "$f")
    if [ ! -f "/output/$bname" ]; then
        echo "  找到: $bname"
        cp "$f" /output/
    fi
done

echo ""
echo "=== 最终产物列表 ==="
ls -lh /output/

DEB_COUNT=$(ls /output/*.deb 2>/dev/null | wc -l)
echo ""
echo "共生成 $DEB_COUNT 个 deb 包"

if [ "$DEB_COUNT" -eq 0 ]; then
    echo ""
    echo "⚠️ 警告: 未生成任何 deb 包！"
    echo "请查看 /output/build.log 获取编译日志"
    # 输出最后 100 行日志便于排查
    echo ""
    echo "=== 构建日志末尾 ==="
    tail -100 /output/build.log 2>/dev/null || true
    exit 1
fi

echo ""
echo "============================================================"
echo " ✅ 编译完成！"
echo "============================================================"
