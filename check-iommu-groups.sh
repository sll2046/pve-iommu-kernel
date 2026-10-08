#!/bin/bash
# ============================================================
# check-iommu-groups.sh
# 查看当前系统的 IOMMU 分组情况
# 用法: bash check-iommu-groups.sh
# ============================================================

echo "============================================================"
echo " IOMMU 分组检查工具"
echo "============================================================"
echo ""

# 检查 IOMMU 是否启用
if dmesg | grep -qi "IOMMU enabled\|AMD-Vi enabled\|DMAR.*IOMMU enabled"; then
    echo "✅ IOMMU 已启用"
else
    echo "⚠️  未检测到 IOMMU 启用，请检查 BIOS 设置和 GRUB 参数"
    echo ""
fi

# 检查内核版本
echo "内核版本: $(uname -r)"
echo ""

# 检查 pcie_acs_override 是否生效
if grep -q "pcie_acs_override" /proc/cmdline 2>/dev/null; then
    ACS_PARAM=$(grep -o "pcie_acs_override=[^ ]*" /proc/cmdline)
    echo "✅ ACS Override 参数: $ACS_PARAM"
else
    echo "⚠️  未设置 pcie_acs_override 内核参数"
fi

echo ""
echo "=== IOMMU 分组详情 ==="
echo ""

shopt -s nullglob

# 按组号排序输出
for g in $(ls -d /sys/kernel/iommu_groups/* 2>/dev/null | sort -V); do
    GROUP_NUM=$(basename "$g")
    DEV_COUNT=$(ls -1 "$g"/devices/ 2>/dev/null | wc -l)

    if [ "$DEV_COUNT" -eq 1 ]; then
        STATUS="✅ (独立分组)"
    else
        STATUS="⚠️  ($DEV_COUNT 个设备在同一组)"
    fi

    echo "── IOMMU Group $GROUP_NUM $STATUS"
    for d in "$g"/devices/*; do
        DEV="${d##*/}"
        DEV_INFO=$(lspci -nns "$DEV" 2>/dev/null || echo "$DEV")
        echo "    $DEV_INFO"
    done
    echo ""
done

if [ ! -d /sys/kernel/iommu_groups ]; then
    echo "❌ /sys/kernel/iommu_groups 目录不存在"
    echo "   可能原因：IOMMU 未启用，或内核不支持 IOMMU"
fi

echo "============================================================"
echo ""
echo "提示："
echo " - ✅ 标记的分组可以安全直通单独设备"
echo " - ⚠️  标记的分组有多个设备，直通时必须将整个组都分配给同一台虚拟机"
echo " - 如果想拆分多设备分组，请安装带 ACS Override 补丁的内核并添加"
echo "   pcie_acs_override=downstream,multifunction 到 GRUB 参数"
