#!/bin/bash
set -e

# ============================================================
# apply-config.sh
# 确保内核配置中 IOMMU / VFIO / PCIe 相关选项已开启
# ============================================================

SRC_DIR="$1"

if [ ! -d "$SRC_DIR" ]; then
    echo "错误: 源码目录 $SRC_DIR 不存在"
    exit 1
fi

cd "$SRC_DIR"
echo "=== 检查内核配置 ==="

# 找到内核源码目录
KERNEL_DIR=""
for d in submodules/ubuntu-* ubuntu-* submodules/linux-* linux; do
    if [ -d "$d" ] && [ -f "$d/Makefile" ]; then
        KERNEL_DIR="$d"
        break
    fi
done

# 查找内核配置文件（PVE 通常有 config-<version> 文件）
KERNEL_CFG=""
for f in config-*.org config-*; do
    if [ -f "$f" ]; then
        KERNEL_CFG="$f"
        echo "找到配置文件: $KERNEL_CFG"
        break
    fi
done

if [ -z "$KERNEL_DIR" ] || [ -z "$KERNEL_CFG" ]; then
    echo "未找到内核配置文件，跳过配置修改（将使用默认配置）"
    exit 0
fi

echo ""
echo "=== 确保 IOMMU / VFIO / PCIe ACS 相关选项开启 ==="

# 需要确保开启的配置选项
CONFIG_OPTIONS=(
    "CONFIG_VFIO=m"
    "CONFIG_VFIO_IOMMU_TYPE1=m"
    "CONFIG_VFIO_VIRQFD=m"
    "CONFIG_VFIO_PCI=m"
    "CONFIG_VFIO_PCI_VGA=y"
    "CONFIG_VFIO_PCI_IGD=y"
    "CONFIG_KVM=m"
    "CONFIG_KVM_INTEL=m"
    "CONFIG_KVM_AMD=m"
    "CONFIG_PCIEPORTBUS=y"
    "CONFIG_PCI_IOV=y"
    "CONFIG_PCI_PRI=y"
    "CONFIG_PCI_PASID=y"
    "CONFIG_PCI_ATS=y"
    "CONFIG_IOMMU_API=y"
    "CONFIG_IOMMU_SUPPORT=y"
    "CONFIG_INTEL_IOMMU=y"
    "CONFIG_INTEL_IOMMU_DEFAULT_ON=y"
    "CONFIG_INTEL_IOMMU_FLOPPY_WA=y"
    "CONFIG_AMD_IOMMU=y"
    "CONFIG_AMD_IOMMU_V2=m"
    "CONFIG_IRQ_REMAP=y"
    "CONFIG_VFIO_NOIOMMU=y"
)

CFG_FILE="$KERNEL_CFG"
echo "修改配置文件: $CFG_FILE"

for opt in "${CONFIG_OPTIONS[@]}"; do
    key="${opt%=*}"
    val="${opt#*=}"

    # 检查配置是否已存在
    if grep -q "^${key}=" "$CFG_FILE" 2>/dev/null || grep -q "^${key} " "$CFG_FILE" 2>/dev/null; then
        old_val=$(grep "^${key}=" "$CFG_FILE" 2>/dev/null | head -1 || echo "")
        if [ "$old_val" != "$opt" ]; then
            # 替换
            sed -i "s|^${key}=.*|${opt}|" "$CFG_FILE"
            echo "  修改: ${key} -> ${val}"
        fi
    elif grep -q "^# ${key} is not set" "$CFG_FILE" 2>/dev/null; then
        # 从注释状态开启
        sed -i "s|^# ${key} is not set|${opt}|" "$CFG_FILE"
        echo "  启用: ${key}=${val}"
    else
        # 追加
        echo "$opt" >> "$CFG_FILE"
        echo "  追加: ${opt}"
    fi
done

echo ""
echo "=== 内核配置检查完成 ==="
