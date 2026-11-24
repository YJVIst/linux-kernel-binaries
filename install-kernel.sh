#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
release=7.3.6
revision=7.3.6-2
repo=YJVIst/linux-kernel-binaries
unit=linux-kernel-binaries-cleanup.service
state=/var/lib/linux-kernel-binaries
self=$(realpath -- "${BASH_SOURCE[0]}")
image=linux-image-${release}_${revision}_amd64.deb
headers=linux-headers-${release}_${revision}_amd64.deb

usage() {
    cat <<'HELP'
用法
  ./install-kernel.sh install [--cleanup] [--from 目录]
  ./install-kernel.sh list-old
  ./install-kernel.sh clean
直接运行等同于 install。--from 指定两个 deb 所在目录，否则通过已登录的 gh 下载。
--cleanup 预约新内核启动后清理旧版本。脚本保留回退内核，不会自动重启。
list-old 预览可清理的已安装软件包。clean 在本版内核下确认后立即清理。
HELP
}
die() { echo "$*" >&2; exit 1; }
as_root() {
    if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi
}
verify_debs() {
    (cd "$1" && sha256sum --check - <<SUMS
f4e779cd57518b08cbe225869d33c6d6bbc2e495bd84ee7e69ccadef3ae294bf  $image
b661086cebe2684682e5ed917cbe4be1e51c56e72246cfd7d4b8c5a23d1caabd  $headers
SUMS
    )
}
check_host() {
    . /etc/os-release
    case "$ID" in debian|ubuntu) ;; *) die "需要 Debian 或 Ubuntu。" ;; esac
    [[ $(dpkg --print-architecture) == amd64 ]] || die "此构建仅支持 amd64。"
    if systemd-detect-virt --quiet --container; then die "请在拥有独立内核的主机中运行。"; fi
}
check_secure_boot() {
    local var=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
    if [[ -d /sys/firmware/efi ]]; then
        [[ -r $var ]] || die "无法读取 UEFI Secure Boot 状态。"
        [[ $(od -An -tu1 -j4 -N1 "$var" | tr -d ' ') == 0 ]] ||
            die "此内核未签名，需要关闭 Secure Boot。"
    fi
}
schedule_cleanup() {
    install -d -m 700 "$state"
    install -m 700 "$self" "$state/install-kernel.sh"
    uname -r > "$state/previous-release"
    cat > "/etc/systemd/system/$unit" <<UNIT
[Unit]
Description=Remove older kernel packages after booting Linux $revision
ConditionKernelVersion=$release
After=local-fs.target
[Service]
Type=oneshot
ExecStart=$state/install-kernel.sh cleanup-on-boot
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable "$unit"
}
install_kernel() {
    local folder="" cleanup=0 args=()
    while (( $# )); do
        case "$1" in
            --cleanup) cleanup=1; shift ;;
            --from) [[ -n ${2:-} ]] || die "--from 缺少目录"; folder=$(realpath -e -- "$2"); shift 2 ;;
            *) die "未知参数 $1" ;;
        esac
    done
    # Download as the caller so gh can use that user's private-repository credentials.
    if [[ -z $folder ]]; then
        command -v gh >/dev/null || die "请安装并登录 gh，或使用 --from 指定本地安装包。"
        tmp=$(mktemp -d)
        trap 'rm -rf -- "$tmp"' EXIT
        gh release download "v$revision" -R "$repo" -p "$image" -p "$headers" -D "$tmp"
        folder=$tmp
    fi
    if (( EUID != 0 )); then
        if (( cleanup )); then args+=(--cleanup); fi
        as_root bash "$self" install --from "$folder" "${args[@]}"
        return
    fi
    check_host
    check_secure_boot
    if (( cleanup )); then
        [[ -d /run/systemd/system ]] || die "预约开机清理需要 systemd。"
    fi
    # Verify the exact private copies passed to APT.
    stage=$(mktemp -d)
    trap 'rm -rf -- "$stage" "${tmp:-}"' EXIT
    install -m 644 -- "$folder/$image" "$folder/$headers" "$stage/"
    verify_debs "$stage"
    apt-get -y --no-remove install "$stage/$image" "$stage/$headers"
    echo "952acbaef3a9e8aa0a07c57afe4687007b5c6de033ab328417fe7d3457ee20a2  /boot/vmlinuz-$release" | sha256sum --check -
    if [[ ! -s /boot/initrd.img-$release ]]; then
        command -v update-initramfs >/dev/null || die "未找到 initrd，请核对本机引导配置后再重启。"
        update-initramfs -c -k "$release"
    fi
    [[ -s /boot/initrd.img-$release ]] || die "未找到 initrd。"
    if command -v update-grub >/dev/null; then update-grub; fi
    if (( cleanup )); then schedule_cleanup; fi
    echo "已安装 $revision。请通过本机引导器选择 $release 并重启。"
}

check_running_build() {
    [[ $(uname -r) == "$release" && $(uname -v) == '#2 SMP PREEMPT_DYNAMIC Tue Nov 24 18:53:38 HKT 2026' ]] ||
        die "请先启动本次发布的 $revision 内核，再清理旧内核。"
    [[ $(dpkg-query -W -f='${db:Status-Status} ${Version}' "linux-image-$release") == "installed $revision" ]] ||
        die "运行内核对应的软件包未正确安装。"
}

plan_cleanup() {
    local pkg status want version prefix fallback="" previous="" listing running
    local -a versions=()
    local -A installed=() held=()
    running=$(uname -r)
    if [[ -r $state/previous-release ]]; then read -r previous < "$state/previous-release"; fi
    listing=$(dpkg-query -W -f='${Package}\t${db:Status-Status}\t${db:Status-Want}\n')
    while read -r pkg status want; do
        [[ $status == installed ]] || continue
        installed[$pkg]=1
        if [[ $want == hold ]]; then held[$pkg]=1; fi
        case "$pkg" in
            linux-image-unsigned-[0-9]*) version=${pkg#linux-image-unsigned-} ;;
            linux-image-[0-9]*) version=${pkg#linux-image-} ;;
            *) continue ;;
        esac
        [[ $version != "$release" && -s /boot/vmlinuz-$version ]] || continue
        versions+=("$version")
    done <<< "$listing"
    (( ${#versions[@]} )) || return 0
    mapfile -t versions < <(printf '%s\n' "${versions[@]}" | sort -Vru)
    for version in "${versions[@]}"; do
        if [[ -s /boot/initrd.img-$version ]]; then fallback=$version; break; fi
    done
    [[ -n $fallback ]] || die "没有找到带 initrd 的回退内核，已停止清理。"
    echo "保留回退内核 $fallback" >&2
    for version in "${versions[@]}"; do
        [[ $version != "$fallback" && $version != "$running" && $version != "$previous" ]] || continue
        dpkg --compare-versions "$version" lt "$release" || continue
        local -a group=()
        for prefix in linux-image linux-image-unsigned linux-modules linux-modules-extra linux-headers; do
            pkg=$prefix-$version
            if [[ -v held[$pkg] ]]; then group=(); break; fi
            if [[ -v installed[$pkg] ]]; then group+=("$pkg"); fi
        done
        candidates+=("${group[@]}")
    done
}
clean_kernel() {
    local mode=$1 answer
    local -a candidates=()
    if [[ $mode != list-old ]]; then check_running_build; fi
    plan_cleanup
    if (( ${#candidates[@]} )); then
        printf '%s\n' "${candidates[@]}"
        if [[ $mode == list-old ]]; then return; fi
        dpkg --no-act --purge "${candidates[@]}"
        if [[ $mode == clean ]]; then
            read -r -p "输入 PURGE 确认移除上述软件包： " answer
            [[ $answer == PURGE ]] || die "已取消。"
        fi
        dpkg --purge "${candidates[@]}"
    else
        echo "没有可清理的旧内核软件包。"
    fi
    if [[ $mode == cleanup-on-boot ]]; then
        systemctl disable "$unit"
        rm -f -- "/etc/systemd/system/$unit" "$state/install-kernel.sh" "$state/previous-release"
        systemctl daemon-reload
    fi
}

action=${1:-install}
if (( $# )); then shift; fi
case "$action" in
    -h|--help|help) usage ;;
    install) install_kernel "$@" ;;
    clean|cleanup-on-boot|list-old)
        (( $# == 0 )) || die "清理命令不接受附加参数。"
        if (( EUID != 0 )) && [[ $action != list-old ]]; then
            as_root bash "$self" "$action"
        else
            check_host
            clean_kernel "$action"
        fi ;;
    *) usage >&2; exit 2 ;;
esac
