#!/usr/bin/env bash
REPO="ZXEB/quarklite"
TOKEN="${1:-$GITHUB_TOKEN}"

if [ -z "$TOKEN" ]; then
  echo "用法: $0 <github_token>"
  echo "或设置环境变量 GITHUB_TOKEN"
  exit 1
fi

api() {
  curl -s -H "Authorization: Bearer $TOKEN" "https://api.github.com/$1"
}

RUN_ID="$(api repos/$REPO/actions/workflows/build.yml/runs?per_page=1 | grep -o '"id": [0-9]*' | head -1 | grep -o '[0-9]*')"
echo "监控 Run #$RUN_ID (repo: $REPO)"

last_job_state=""

while true; do
  clear 2>/dev/null || true
  echo "===== GitHub Actions 构建监控 (每10秒刷新) ====="
  echo "时间: $(date '+%H:%M:%S')"
  echo

  status="$(api repos/$REPO/actions/runs/$RUN_ID | grep -o '"status": "[^"]*"' | cut -d'"' -f4)"
  conclusion="$(api repos/$REPO/actions/runs/$RUN_ID | grep -o '"conclusion": [^,]*' | cut -d' ' -f2 | tr -d '"')"

  case "$status" in
    completed)
      echo "⚠️  当前状态: **已完成 (结论: ${conclusion:-null})**"
      ;;
    in_progress)
      echo "▶️  当前状态: **进行中...**"
      ;;
    queued)
      echo "⏳ 当前状态: **排队中...**"
      ;;
    *)
      echo "当前状态: $status"
      ;;
  esac
  echo

  job_state="$(api repos/$REPO/actions/runs/$RUN_ID/jobs | python3 -c '
import json,sys
d=json.load(sys.stdin)
for j in d["jobs"]:
    print(f"  {j[\"name\"]:<18} {j[\"status\"]:<12} {j.get(\"conclusion\") or \"-\"}")
' 2>/dev/null)"

  if [ -n "$job_state" ]; then
    echo "---- Job 状态 ----"
    echo "$job_state"
  fi

  if [ "$status" = "completed" ]; then
    done_dir="$(date '+%H%M%S')_done"
    echo
    case "${conclusion}" in
      success)
        echo "✅ 构建成功！产物在 Actions 页面:"
        echo "   https://github.com/$REPO/actions/runs/$RUN_ID"
        ;;
      failure)
        echo "❌ 构建失败。日志:"
        echo "   https://github.com/$REPO/actions/runs/$RUN_ID"
        ;;
      cancelled)
        echo "⏹️ 构建被取消。"
        ;;
      *)
        echo "构建结束: $conclusion"
        ;;
    esac
    exit 0
  fi

  sleep 10
done