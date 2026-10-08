# PVE IOMMU Kernel Builder

自动在 GitHub Actions 上编译带 **ACS Override 增强补丁** 的 Proxmox VE 内核，解决 IOMMU 分组不独立导致的 PCIe 设备直通问题（GPU 直通、NVMe 直通、网卡直通等）。

## 🔍 解决什么问题？

许多主板（特别是 **J3455/N3150/J4125/N5105** 等消费级 ITX 主板、部分老芯片组）即使开启了 IOMMU 和 `pcie_acs_override=downstream,multifunction` 参数，仍会出现多个 PCIe 设备被挤在同一个 IOMMU Group 的情况，导致无法单独直通某个设备给虚拟机。

本项目通过 GitHub Actions 自动编译打了增强版 ACS Override 补丁的 PVE 内核，强制所有 PCIe 设备获得独立的 IOMMU 分组。

## 🚀 快速使用

### 方法一：GitHub Actions 自动编译（推荐）

1. **Fork 本仓库**到你的 GitHub 账号
2. 点击仓库页面的 **Actions** 标签
3. 选择左侧 **Build PVE Kernel with IOMMU ACS Override**
4. 点击 **Run workflow**，填写参数：
   - **PVE 内核分支**: `master`（最新）或 `stable-8.2`/`stable-8.1` 等
   - **内核后缀**: `-iommu`（自定义标识）
   - **应用 ACS 补丁**: `true`
5. 点击 **Run workflow** 开始编译
6. 编译完成后，在对应 run 的页面底部 **Artifacts** 下载编译产物

编译时间通常为 **1-3 小时**（取决于 GitHub Actions 机器负载和内核版本）。

### 方法二：自动定时编译

仓库已配置每周日 UTC 02:00（北京时间 10:00）自动触发编译，你也可以修改 `.github/workflows/build.yml` 中的 cron 表达式调整频率。

## 📦 安装编译好的内核

下载 Artifacts 压缩包后解压，将所有 `.deb` 文件上传到 PVE 宿主机：

```bash
# 1. 安装内核
dpkg -i pve-kernel-*.deb pve-headers-*.deb
apt-get install -f -y

# 2. 修改 GRUB 开启 IOMMU + ACS override
nano /etc/default/grub
```

**Intel 平台** 修改为：
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt pcie_acs_override=downstream,multifunction video=efifb:off"
```

**AMD 平台** 修改为：
```
GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction video=efifb:off"
```

```bash
# 3. 更新 GRUB 并重启
update-grub
reboot

# 4. 重启后验证
uname -r  # 确认内核版本带 -iommu 后缀
dmesg | grep -e DMAR -e IOMMU  # 确认 IOMMU 已启用
bash check-iommu-groups.sh  # 查看 IOMMU 分组
```

详细安装说明（含 VFIO 配置、GPU 直通黑名单、回滚方法）见下载包中的 `INSTALL.md`。

## 🛠️ 本地编译

如果你想在本地编译（需要 Linux 环境，推荐 Debian/Ubuntu）：

```bash
# 克隆仓库
git clone https://github.com/你的用户名/pve-iommu-kernel.git
cd pve-iommu-kernel

# 使用 Docker 编译（推荐，环境一致性最好）
docker build -t pve-kernel-builder .
docker run --rm \
  -v "$(pwd)/scripts:/build/scripts:ro" \
  -v "$(pwd)/output:/output" \
  -e PVE_BRANCH=master \
  -e KERNEL_SUFFIX=-iommu \
  -e APPLY_ACS=true \
  -e BUILD_CORES=$(nproc) \
  pve-kernel-builder
```

## 📁 项目结构

```
pve-iommu-kernel/
├── .github/workflows/
│   └── build.yml          # GitHub Actions 工作流配置
├── scripts/
│   ├── build-in-docker.sh # Docker 容器内的主编译脚本
│   ├── apply-acs-patch.sh # 应用 ACS Override 补丁
│   └── apply-config.sh    # 修改内核配置（确保 IOMMU/VFIO 开启）
├── Dockerfile             # 编译环境 Dockerfile（Debian Bookworm）
└── README.md              # 本文件
```

## ⚠️ 注意事项

1. **内核替换有风险** - 请确保你有控制台/IPMI 访问权限，万一新内核无法启动可以在 GRUB 中选择旧内核回退。
2. **ACS Override 有安全风险** - 它绕过了 PCIe 设备的硬件隔离检查，理论上存在 DMA 攻击风险。仅在你信任的硬件和环境中使用。
3. **首次启动可能较慢** - 新内核第一次启动时需要编译 ZFS 等模块，可能比平时慢几分钟。
4. **PVE 版本兼容** - master 分支跟踪 Proxmox 最新开发版内核，建议生产环境使用 `stable-*` 分支。

## 🔗 参考项目

- [Proxmox VE pve-kernel 官方源码](https://git.proxmox.com/?p=pve-kernel.git)
- [yfdoor/PVE-Kernel](https://github.com/yfdoor/PVE-Kernel) - 原始 IOMMU 分组修复项目
- [fabianishere/pve-edge-kernel](https://github.com/fabianishere/pve-edge-kernel) - 社区 PVE 边缘内核
- [Alex Williamson's ACS override patch](https://vfio.blogspot.com/) - ACS Override 补丁原作者

## 📄 许可证

本项目仅提供自动化编译脚本，内核本身遵循其原有许可证（GPL v2）。
使用本项目编译出的内核请遵守 Linux 内核及 Proxmox 的相关许可协议。
