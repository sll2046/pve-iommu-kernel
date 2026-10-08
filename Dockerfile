# ============================================================
# Dockerfile: PVE 内核编译环境（Debian Bookworm 匹配 PVE 8.x）
# ============================================================
FROM debian:bookworm

ENV DEBIAN_FRONTEND=noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN=true

# 安装编译依赖
RUN sed -i 's|deb.debian.org|mirrors.ustc.edu.cn|g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's|deb.debian.org|mirrors.ustc.edu.cn|g' /etc/apt/sources.list 2>/dev/null || true

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential fakeroot devscripts \
    git wget curl rsync ca-certificates \
    bc bison flex libssl-dev libelf-dev \
    libncurses-dev dwarves pahole \
    debhelper dh-python dh-make \
    python3 python3-dev python3-sphinx \
    cpio kmod zstd lz4 xz-utils \
    asciidoc-base xmlto docbook-xsl \
    quilt patchutils \
    gcc g++ make cmake \
    autoconf automake libtool pkg-config \
    gawk bzip2 gzip \
    equivs apt-utils lintian \
    libpve-common-perl \
    spl-dkms zfs-dkms \
    uuid-dev libblkid-dev libattr1-dev \
    libudev-dev libaio-dev libssl-dev \
    libpam0g-dev libcap-dev \
    python3-distutils python3-setuptools \
    nano vim \
    && rm -rf /var/lib/apt/lists/*

# 添加 Proxmox 软件源（用于解决构建依赖，但不干扰系统）
RUN echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-sub.list && \
    wget -q http://download.proxmox.com/debian/proxmox-release-bookworm.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg && \
    apt-get update && \
    apt-get install -y --no-install-recommends pve-headers-$(uname -r) 2>/dev/null || true && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 复制构建脚本
COPY scripts/ /build/scripts/
RUN chmod +x /build/scripts/*.sh

# 设置编译入口
ENTRYPOINT ["/bin/bash", "/build/scripts/build-in-docker.sh"]
