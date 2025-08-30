#!/usr/bin/env bash
#
# chmod +x wpn-zip-handler.sh
#
# wpn-zip-handler.sh - WireGuard VPN 压缩包处理脚本
#
# 功能：
#   1. 检索当前目录下所有 wpn-*.zip 压缩包
#   2. 解压缩到对应目录
#   3. 对解压后的所有 shell 脚本授予执行权限
#
# 使用场景：
#   将此脚本与 wpn-*.zip 压缩包一起上传到服务器，然后执行
#   脚本会直接在终端输出详细执行过程
#
# 作者：WPN 项目组
# 版本：1.0.0
#

set -euo pipefail

# ==================== 配置参数 ====================
readonly SCRIPT_NAME="wpn-zip-handler"
readonly SCRIPT_VERSION="1.0.0"
readonly WORK_DIR="${PWD}"

# ==================== 函数定义 ====================

# 初始化输出
init_output() {
  echo "==============================================="
  echo "$(date '+%F %T') ${SCRIPT_NAME} v${SCRIPT_VERSION} 开始执行"
  echo "$(date '+%F %T') 工作目录: ${WORK_DIR}"
  echo "$(date '+%F %T') 当前用户: $(whoami)"
  echo "==============================================="
}


# 查找 wpn-*.zip 文件
find_zip_files() {
  local -a zip_files

  echo "$(date '+%F %T') 正在搜索 wpn-*.zip 压缩包..."

  # 安全处理文件名（支持空格等特殊字符）
  # 注意：mapfile 在 macOS 的旧版 bash 中不可用，使用 while read 替代
  zip_files=()
  while IFS= read -r -d '' file; do
    zip_files+=("$file")
  done < <(find "${WORK_DIR}" -maxdepth 1 -type f -name 'wpn-*.zip' -print0 2>/dev/null)

  if [[ ${#zip_files[@]} -eq 0 ]]; then
    echo "$(date '+%F %T') 未找到任何 wpn-*.zip 压缩包"
    return 1
  fi

  echo "$(date '+%F %T') 找到 ${#zip_files[@]} 个压缩包:"
  for zip in "${zip_files[@]}"; do
    echo "  - $(basename "${zip}")"
  done

  # 将结果存储到全局数组
  ZIP_FILES=("${zip_files[@]}")
  return 0
}

# 解压单个 zip 文件
extract_zip() {
  local zip_file="$1"
  local zip_basename
  local dest_dir
  local temp_dir

  zip_basename="$(basename "${zip_file}")"
  # 去掉 .zip 后缀作为目标目录名
  dest_dir="${WORK_DIR}/${zip_basename%.zip}"

  echo ""
  echo "$(date '+%F %T') 处理压缩包: ${zip_basename}"

  # 检查目标目录是否已存在
  if [[ -d "${dest_dir}" ]]; then
    echo "$(date '+%F %T') 警告: 目标目录已存在: ${dest_dir}"
    echo "$(date '+%F %T') 跳过此压缩包的解压"
    return 1
  fi

  # 创建临时目录用于安全解压
  temp_dir=$(mktemp -d "${WORK_DIR}/.tmp.XXXXXX")

  # 设置 trap 确保清理临时目录
  trap 'rm -rf "${temp_dir}"' EXIT

  echo "$(date '+%F %T') 解压到临时目录: ${temp_dir}"

  # 解压文件
  if unzip -q "${zip_file}" -d "${temp_dir}"; then
    echo "$(date '+%F %T') 解压成功"

    # 移动到最终目录
    mv "${temp_dir}" "${dest_dir}"
    echo "$(date '+%F %T') 文件已移动到: ${dest_dir}"

    # 清除 trap
    trap - EXIT

    # 返回目标目录供后续处理
    echo "${dest_dir}"
    return 0
  else
    echo "$(date '+%F %T') 错误: 解压失败 - ${zip_basename}"
    rm -rf "${temp_dir}"
    trap - EXIT
    return 1
  fi
}

# 为 shell 脚本设置执行权限
set_executable_permissions() {
  local target_dir="$1"
  local -a shell_files
  local count=0

  echo "$(date '+%F %T') 正在设置 shell 脚本执行权限..."

  # 查找所有 .sh 文件
  # 使用 while read 替代 mapfile 以兼容 macOS
  shell_files=()
  while IFS= read -r -d '' file; do
    shell_files+=("$file")
  done < <(find "${target_dir}" -type f -name '*.sh' -print0 2>/dev/null)

  if [[ ${#shell_files[@]} -eq 0 ]]; then
    echo "$(date '+%F %T') 未找到任何 shell 脚本文件"
    return 0
  fi

  # 批量设置执行权限
  for script_file in "${shell_files[@]}"; do
    if chmod +x "${script_file}"; then
      count=$((count + 1))
      # 使用替代方法获取相对路径，兼容 macOS
      local rel_path="${script_file#${target_dir}/}"
      echo "  [✓] ${rel_path}"
    else
      local rel_path="${script_file#${target_dir}/}"
      echo "  [✗] ${rel_path} - 设置权限失败"
    fi
  done

  echo "$(date '+%F %T') 共设置 ${count} 个 shell 脚本可执行权限"

  return 0
}

# 错误处理
error_handler() {
  local line_no=$1
  local exit_code=$2

  echo ""
  echo "$(date '+%F %T') 错误: 脚本在第 ${line_no} 行失败，退出码: ${exit_code}"
  echo "$(date '+%F %T') ${SCRIPT_NAME} 执行异常结束"
  echo "==============================================="

  exit "${exit_code}"
}

# 清理函数
cleanup() {
  local exit_code=$?

  if [[ ${exit_code} -eq 0 ]]; then
    echo ""
    echo "$(date '+%F %T') ${SCRIPT_NAME} 执行成功完成"
  fi

  echo "==============================================="
}

# ==================== 主函数 ====================

main() {
  # 设置错误处理
  trap 'error_handler ${LINENO} $?' ERR
  trap cleanup EXIT

  # 初始化输出
  init_output

  # 声明全局数组存储找到的 zip 文件
  declare -a ZIP_FILES

  # 查找 zip 文件
  if ! find_zip_files; then
    echo "$(date '+%F %T') 没有需要处理的压缩包，脚本退出"
    exit 0
  fi

  # 处理每个 zip 文件
  local success_count=0
  local fail_count=0

  for zip_file in "${ZIP_FILES[@]}"; do
    if dest_dir=$(extract_zip "${zip_file}"); then
      # 提取目录路径（extract_zip 输出的最后一行）
      dest_dir=$(echo "${dest_dir}" | tail -n1)

      # 设置脚本执行权限
      if set_executable_permissions "${dest_dir}"; then
        success_count=$((success_count + 1))
      fi
    else
      fail_count=$((fail_count + 1))
    fi
  done

  # 汇总结果
  echo ""
  echo "$(date '+%F %T') ===== 处理结果汇总 ====="
  echo "$(date '+%F %T') 成功处理: ${success_count} 个压缩包"
  if [[ ${fail_count} -gt 0 ]]; then
    echo "$(date '+%F %T') 处理失败: ${fail_count} 个压缩包"
  fi

  # 如果有失败的，返回非零退出码
  if [[ ${fail_count} -gt 0 ]]; then
    exit 1
  fi
}

# ==================== 脚本入口 ====================

# 只有直接执行脚本时才运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
