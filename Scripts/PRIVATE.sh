#!/bin/bash
# SPDX-License-Identifier: MIT

#私有扩展脚本：由 Scripts/Packages.sh 末尾 source 引入
#运行时机：feeds 安装完成之后，.config 拼装与 make defconfig 之前
#运行目录：./wrt/package/  （因此固件根目录为 ../ ，files 覆盖目录为 ../files）
#注意：本文件是被 source 的，提前退出必须用 return，不能用 exit（否则会终止 Packages.sh）

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
	echo "Applied private rootfs overlay:"
	find "$FILES_DIR" -type f | sed 's|^\.\./|  |'
else
	echo "Private config repo is empty, nothing to apply."
fi

rm -rf "$PRIVATE_DIR"
echo " "
