#!/bin/bash
# 星链 · 云端构建推送脚本（拿到 GitHub PAT 后由 ZCode 执行，也可手动跑）
# 用法：GHTOKEN=ghp_xxxx bash push-and-build.sh
set -e
TOKEN="${GHTOKEN:?请先 export GHTOKEN=你的令牌}"
API="https://api.github.com"
AUTH="Authorization: Bearer $TOKEN"
REPO="starlink-workbench"

echo "==> 1. 创建私有仓库 $REPO"
curl -s -X POST "$API/user/repos" -H "$AUTH" -H "Accept: application/vnd.github+json" \
  -d "{\"name\":\"$REPO\",\"private\":true}" | grep -q full_name && echo "  仓库已建" || echo "  （可能已存在，继续）"

echo "==> 2. 推送代码（触发 Actions 构建）"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${TOKEN}@github.com/starlink-bot-test/$REPO.git"
# 用户名以令牌换取的实际账号为准（脚本自动探测）
LOGIN=$(curl -s "$API/user" -H "$AUTH" | grep -o '"login": *"[^"]*"' | cut -d'"' -f4)
git remote set-url origin "https://${LOGIN}:${TOKEN}@github.com/${LOGIN}/${REPO}.git"
git branch -M main
git push -u origin main 2>&1 | tail -3

echo "==> 3. 等待 Actions 构建完成（首次约 3-6 分钟）"
RUN=""
for i in $(seq 1 60); do
  sleep 10
  RUN=$(curl -s "$API/repos/${LOGIN}/${REPO}/actions/runs?per_page=1" -H "$AUTH" \
    | grep -o '"id": *[0-9]*' | head -1 | grep -o '[0-9]*')
  STATUS=$(curl -s "$API/repos/${LOGIN}/${REPO}/actions/runs/${RUN}" -H "$AUTH" \
    | grep -o '"status": *"[^"]*"' | head -1 | cut -d'"' -f4)
  echo "  [${i}] run ${RUN} → ${STATUS}"
  [ "$STATUS" = "completed" ] && break
done
[ "$STATUS" = "completed" ] || { echo "构建超时/失败，去 Actions 页看日志"; exit 1; }

echo "==> 4. 下载免签名 ipa 到桌面"
ART=$(curl -s "$API/repos/${LOGIN}/${REPO}/actions/runs/${RUN}/artifacts" -H "$AUTH" \
  | grep -o '"archive_download_url": *"[^"]*"' | cut -d'"' -f4)
curl -sL -H "$AUTH" "$ART" -o "$HOME/Desktop/starlink-unsigned.ipa"
ls -la "$HOME/Desktop/starlink-unsigned.ipa"
echo "==> 完成。下一步：Sideloadly/爱思 + Apple ID 签名安装（手机已插电脑）"
