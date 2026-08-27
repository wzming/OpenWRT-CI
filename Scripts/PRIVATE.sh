#!/bin/bash
# SPDX-License-Identifier: MIT

#私有扩展脚本：由 Scripts/Packages.sh 末尾 source 引入
#运行时机：feeds 安装完成之后，.config 拼装与 make defconfig 之前
#运行目录：./wrt/package/  （因此固件根目录为 ../ ，files 覆盖目录为 ../files）
#注意：本文件是被 source 的，提前退出必须用 return，不能用 exit（否则会终止 Packages.sh）

#预置 mihomo geo 数据，避免首次开机联网下载
#目标目录即 nikki.init 传给 mihomo 的 -d 工作目录：/etc/nikki/run
#geosite.dat 总是使用；geoip.metadb 用于默认 mmdb 模式，geoip.dat 用于 geodata-mode=dat
#两种模式的文件都预置，切换 GeoIP 格式时无需重新联网下载
GEO_DIR="../files/etc/nikki/run"
GEO_BASE="https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest"

mkdir -p "$GEO_DIR"

for GEO_FILE in geosite.dat geoip.metadb geoip.dat; do
	echo "Downloading $GEO_FILE ..."
	#下载失败时删除半截文件：残缺的 geo 文件会导致 mihomo 启动崩溃，
	#删掉后退化为首次开机自行下载，比留下坏文件安全
	if curl -fsSL --retry 3 --connect-timeout 15 \
		-o "$GEO_DIR/$GEO_FILE" "$GEO_BASE/$GEO_FILE"; then
		echo "  ok: $(du -h "$GEO_DIR/$GEO_FILE" | cut -f1)"
	else
		echo "  failed, removing partial file"
		rm -f "$GEO_DIR/$GEO_FILE"
	fi
done

echo " "

#预置 OpenClash 内核与 geo 数据
#内核路径见 openclash init 的 do_run_file()：非小闪存机型为 /etc/openclash/core/clash_meta
#tar 包内二进制名为 clash，需重命名并置 4755（openclash_core.sh 运行时也是这么做的）
#geo 数据源与 nikki 不同，取自 openclash_geo.sh 中的默认地址
OC_DIR="../files/etc/openclash"
OC_CORE_BASE="https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta"

#架构映射对照 openclash uci-defaults 的 DISTRIB_ARCH 分支
#本项目 qualcommax/qualcommbe/mediatek/rockchip 均为 aarch64，仅 x86 为 amd64
case "$WRT_TARGET" in
	x86)        OC_ARCH="linux-amd64-v1" ;;
	*)          OC_ARCH="linux-arm64" ;;
esac

mkdir -p "$OC_DIR/core"

echo "Downloading OpenClash core ($OC_ARCH) ..."
if curl -fsSL --retry 3 --connect-timeout 15 \
	-o /tmp/oc_core.tar.gz "$OC_CORE_BASE/clash-$OC_ARCH.tar.gz" \
	&& tar -zxf /tmp/oc_core.tar.gz -C /tmp clash; then
	mv -f /tmp/clash "$OC_DIR/core/clash_meta"
	chmod 4755 "$OC_DIR/core/clash_meta"
	echo "  ok: $(du -h "$OC_DIR/core/clash_meta" | cut -f1)"
else
	echo "  failed, removing partial core"
	rm -f "$OC_DIR/core/clash_meta"
fi
rm -f /tmp/oc_core.tar.gz /tmp/clash

#目标文件名 → 下载地址，与 openclash_geo.sh 的 update_one 调用保持一致
for OC_GEO in \
	"GeoSite.dat|https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat" \
	"GeoIP.dat|https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat" \
	"Country.mmdb|https://raw.githubusercontent.com/alecthw/mmdb_china_ip_list/release/lite/Country.mmdb" \
	"ASN.mmdb|https://github.com/xishang0128/geoip/releases/latest/download/GeoLite2-ASN.mmdb" ; do
	OC_NAME="${OC_GEO%%|*}"
	OC_URL="${OC_GEO#*|}"
	echo "Downloading $OC_NAME ..."
	if curl -fsSL --retry 3 --connect-timeout 15 -o "$OC_DIR/$OC_NAME" "$OC_URL"; then
		echo "  ok: $(du -h "$OC_DIR/$OC_NAME" | cut -f1)"
	else
		echo "  failed, removing partial file"
		rm -f "$OC_DIR/$OC_NAME"
	fi
done

echo " "

PRIVATE_DIR="/tmp/private-config"

if [ -z "$PRIVATE_TOKEN" ] || [ -z "$PRIVATE_REPO" ]; then
	echo "PRIVATE_TOKEN or PRIVATE_REPO not set, skip private config."
	return 0
fi

echo " "
echo "Cloning private config: $PRIVATE_REPO (branch: $WRT_CONFIG)"

rm -rf "$PRIVATE_DIR"

#按机型分支拉取，分支名与 WRT_CONFIG 一致（如 IPQ60XX-WIFI-YES）
#URL 中含 token，全程不回显；GitHub 会对已注册的 secret 自动打码
if ! git clone --depth=1 --single-branch --branch "$WRT_CONFIG" \
	"https://x-access-token:$PRIVATE_TOKEN@github.com/$PRIVATE_REPO.git" \
	"$PRIVATE_DIR" 2>/dev/null; then
	echo "Private config branch '$WRT_CONFIG' not found or clone failed, skip."
	return 0
fi

rm -rf "$PRIVATE_DIR/.git"

#将私有仓库内容覆盖进 files/ ，编译时会烤进固件 rootfs
FILES_DIR="../files"
mkdir -p "$FILES_DIR"

if [ -n "$(ls -A "$PRIVATE_DIR" 2>/dev/null)" ]; then
	cp -rf "$PRIVATE_DIR"/. "$FILES_DIR"/
	#仅输出文件数量：公开仓库的 Actions 日志任何人可见，路径本身也算泄露
	echo "Applied private rootfs overlay: $(find "$PRIVATE_DIR" -type f | wc -l) file(s)"
	#标记本次固件含私有配置，供 Encrypt Firmware 步骤判断是否必须加密
	[ -n "$GITHUB_ENV" ] && echo "WRT_PRIVATE=true" >> "$GITHUB_ENV"
else
	echo "Private config repo is empty, nothing to apply."
fi

rm -rf "$PRIVATE_DIR"
echo " "
