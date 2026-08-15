#!/bin/bash
# 启动打包后的应用，10 秒后对进程树做一次资源采样，然后退出。
# 采样项：RSS（KB）、%CPU、启动时长。只读，不会修改应用。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/DeepSeek Harness Shell.app"

echo "== 应用体积 =="
du -sh "$APP"
BIN="$APP/Contents/MacOS/DeepSeekHarnessShell"
echo "二进制: $(du -h "$BIN" | cut -f1)"

echo "== 启动应用 =="
open "$APP"
sleep 10

echo "== 采样应用进程树 =="
MAIN_PID="$(pgrep -x DeepSeekHarnessShell | head -1 || true)"
if [ -z "$MAIN_PID" ]; then
  echo "未找到应用进程"
  exit 1
fi

# 递归收集后代进程（dsh web、WebKit XPC 等）
collect_descendants() {
  local parent="$1"
  local child
  for child in $(pgrep -P "$parent" 2>/dev/null || true); do
    echo "$child"
    collect_descendants "$child"
  done
}

PIDS="$MAIN_PID $(collect_descendants "$MAIN_PID")"
echo "进程数: $(echo $PIDS | wc -w | tr -d ' ')"
printf "%-8s %-10s %-6s %s\n" "PID" "RSS(KB)" "CPU%" "COMMAND"
TREE_RSS=0
for pid in $PIDS; do
  read -r rss cpu command <<< "$(ps -o rss= -o %cpu= -o command= -p "$pid")"
  TREE_RSS=$((TREE_RSS + rss))
  printf "%-8s %-10s %-6s %s\n" "$pid" "$rss" "$cpu" "$command"
done

echo
echo "== 汇总 =="
APP_RSS=$(ps -o rss= -p "$MAIN_PID" | tr -d ' ')
echo "主进程 RSS: $((APP_RSS / 1024)) MB"
echo "应用进程树 RSS 合计: $((TREE_RSS / 1024)) MB"
echo "应用包体积: $(du -sk "$APP" | cut -f1) KB"

echo "== 退出应用 =="
osascript -e 'tell application id "com.deepseek.harness.shell" to quit' 2>/dev/null || pkill -x DeepSeekHarnessShell || true
sleep 3
pgrep -fl "dsh web" || echo "dsh 子进程已清理"
