#!/usr/bin/env bash
# scripts/pr-open.sh 的測試。gh 一律換成記錄呼叫的假程式（mktemp 目錄、放在 PATH 最前面），
# 絕不呼叫真的 gh pr create。私有擴充換成暫存目錄裡固定回 0／1 的 pr-scan.sh。
# 每個案例自己設或清空 GITHUB_WORKFLOW_PRIVATE_DIR，不吃跑測試那台的設定。
# 每個案例印一行「ok <案例名>」或「not ok <案例名>」。
# 票號（井號＋數字）在執行時組出，不直接寫進本檔。
set -uo pipefail
TPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd -P)" || exit 9
PLUGIN="$(cd "${TPO_DIR}/.." && pwd -P)" || exit 9
S="${PLUGIN}/scripts/pr-open.sh"
[ -f "${S}" ] || { echo "not ok 檔案不存在：${S}"; exit 1; }

T="$(mktemp -d)" || exit 9
trap 'rm -rf "${T}"' EXIT
mkdir -p "${T}/bin" "${T}/priv-pass" "${T}/priv-fail" "${T}/priv-empty"
# 假 gh：記下每一次呼叫。
#   repo view → FAKE_VIS（PUBLIC／PRIVATE／fail）
#   pr create → 記下標題與內文，印假網址
#   pr view   → FAKE_VIEW（ok＝原樣讀回／fail＝讀回失敗／dirty＝讀回多了一行 READBACK-LEAK）
cat > "${T}/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_LOG}"
case "$1 $2" in
  "repo view")
    case "${FAKE_VIS}" in fail) echo "HTTP 502" >&2; exit 1 ;; *) echo "${FAKE_VIS}" ;; esac ;;
  "pr create")
    shift 2
    while [ $# -gt 0 ]; do
      case "$1" in --title) printf '%s' "$2" > "${FAKE_STATE}.title"; shift ;; --body-file) cp "$2" "${FAKE_STATE}.body"; shift ;; esac
      shift
    done
    echo "https://example.test/fake/repo/pull/7" ;;
  "pr view")
    case "${FAKE_VIEW}" in
      fail) echo "HTTP 502" >&2; exit 1 ;;
      dirty) cat "${FAKE_STATE}.title"; echo; cat "${FAKE_STATE}.body"; echo "READBACK-LEAK" ;;
      *) cat "${FAKE_STATE}.title"; echo; cat "${FAKE_STATE}.body" ;;
    esac ;;
  *) echo "假 gh 不認得：$*" >&2; exit 3 ;;
esac
FAKE
chmod +x "${T}/bin/gh"
# 私有擴充：pass 只擋讀回時多出來的那一行；fail 固定回 1；empty 沒有 pr-scan.sh
printf '%s\n' '#!/usr/bin/env bash' 'if grep -q READBACK-LEAK; then exit 1; fi; exit 0' > "${T}/priv-pass/pr-scan.sh"
printf '%s\n' '#!/usr/bin/env bash' 'cat > /dev/null; exit 1' > "${T}/priv-fail/pr-scan.sh"
export PATH="${T}/bin:${PATH}" FAKE_LOG="${T}/log" FAKE_STATE="${T}/state"

printf '%s\n' '改寫說明' > "${T}/title"
printf '%s\n' '## 摘要' '改了說明文字' > "${T}/clean"
printf '## 摘要\n改了說明文字\nCloses %s%s\n' '#' 5 > "${T}/bare"
printf '## 摘要\nCloses some-owner/some-repo%s%s\n' '#' 5 > "${T}/ownerrepo"
printf '## 摘要\n見 app%s%s 的說明\n' '#' 12 > "${T}/short"
printf '## 摘要\n見 https://github.com/some-owner/some-repo/issues/%s\n' 5 > "${T}/url-issue"
printf '## 摘要\n見 https://github.com/some-owner/some-repo/pull/%s。\n' 5 > "${T}/url-pull"
printf '## 摘要\n修好 GH-%s 的問題\n' 5 > "${T}/gh-n"
printf '## 摘要\n修好 gh-%s 的問題\n' 5 > "${T}/gh-n-lower"
printf '## 摘要\nCloses %s%s\n' '＃' 5 > "${T}/fullwidth"
printf '## 摘要\n見 https://github.com/some-owner/some-repo/blob/main/README.md 與 GHz-5 規格\n' > "${T}/url-blob"
printf '## 摘要\n見 https://GitHub.com/some-owner/some-repo/issues/%s\n' 5 > "${T}/url-upper"
printf '## 摘要\n見 https://WWW.GITHUB.COM/some-owner/some-repo/pull/%s\n' 5 > "${T}/url-www-upper"
printf '## 摘要\nCloses %s%s%s\n' '#' '#' 5 > "${T}/double-hash"
printf '## 摘要\n見 &%s%s; 的寫法與 &%s%s%s;\n' '#' 39 '#' '#' 39 > "${T}/html-entity"

PASS=0 FAILN=0
calls() { grep -c "^$1" "${FAKE_LOG}"; } # 某種 gh 呼叫的次數
# run <可見度> <讀回> <私有擴充目錄或空> <內文檔>；結果放在 rc、out
run() {
  : > "${FAKE_LOG}"; rm -f "${FAKE_STATE}".*
  export FAKE_VIS="$1" FAKE_VIEW="$2"
  if [ -n "$3" ]; then export GITHUB_WORKFLOW_PRIVATE_DIR="$3"; else unset GITHUB_WORKFLOW_PRIVATE_DIR; fi
  bash "${S}" fake/repo main feat/x "${T}/title" "$4" > "${T}/out" 2> "${T}/err"; rc=$?
  out="$(cat "${T}/out")"
}
verdict() { # verdict <案例名> <條件…>：條件全部成立 → ok
  local name="$1"; shift
  if "$@"; then echo "ok ${name}"; PASS=$((PASS + 1))
  else echo "not ok ${name}"; echo "  # rc=${rc} 呼叫：$(tr '\n' ';' < "${FAKE_LOG}")"; FAILN=$((FAILN + 1)); fi
}
URL="https://example.test/fake/repo/pull/7"

if [ "$(command -v gh)" = "${T}/bin/gh" ]; then echo "ok 腳本拿到的是假 gh"; PASS=$((PASS + 1))
else echo "not ok 腳本拿到的是假 gh（$(command -v gh)）"; echo "停：不是假 gh 就不跑"; exit 1; fi

run PUBLIC ok "${T}/priv-fail" "${T}/clean"
c_scan_fail() { [ "${rc}" -eq 1 ] && [ "$(calls 'pr create')" -eq 0 ]; }
verdict '掃描器 rc=1：沒呼叫 gh pr create' c_scan_fail

run PUBLIC ok "${T}/priv-empty" "${T}/clean"
c_no_scanner() { [ "${rc}" -eq 1 ] && [ "$(calls 'pr create')" -eq 0 ]; }
verdict '有私有擴充但沒有 pr-scan.sh：沒呼叫 gh pr create' c_no_scanner

run PUBLIC fail "${T}/priv-pass" "${T}/clean"
c_view_fail() { [ "${rc}" -ne 0 ] && [ "$(calls 'pr create')" -eq 1 ] && [ "$(calls 'pr view')" -eq 1 ] && [ "${out}" = "${URL}" ]; }
verdict '讀回失敗：rc 非 0' c_view_fail

run PUBLIC dirty "${T}/priv-pass" "${T}/clean"
c_view_dirty() { [ "${rc}" -ne 0 ] && [ "$(calls 'pr create')" -eq 1 ] && [ "$(calls 'pr view')" -eq 1 ] && [ "${out}" = "${URL}" ]; }
verdict '讀回後掃描 rc=1：rc 非 0' c_view_dirty

run PUBLIC ok '' "${T}/bare"
c_builtin() { [ "${rc}" -eq 1 ] && [ "$(calls 'pr create')" -eq 0 ] && grep -q '內建檢查' "${T}/err"; }
verdict '沒有私有擴充：內建檢查擋裸票號、沒呼叫 gh pr create' c_builtin

run PUBLIC ok '' "${T}/ownerrepo"
verdict '沒有私有擴充：內建檢查擋 owner/repo#N、沒呼叫 gh pr create' c_builtin

run PUBLIC ok '' "${T}/short"
verdict '沒有私有擴充：內建檢查擋短名#N、沒呼叫 gh pr create' c_builtin

run PUBLIC ok '' "${T}/clean"
c_clean() { [ "${rc}" -eq 0 ] && [ "$(calls 'pr create')" -eq 1 ] && [ "$(calls 'pr view')" -eq 1 ] && [ "${out}" = "${URL}" ]; }
verdict '乾淨：呼叫 gh pr create 一次並讀回' c_clean

run PRIVATE ok "${T}/priv-fail" "${T}/bare"
c_private() { [ "${rc}" -eq 0 ] && [ "$(calls 'pr create')" -eq 1 ] && [ "$(calls 'pr view')" -eq 0 ] && [ "${out}" = "${URL}" ]; }
verdict '私有 repo：不掃描、呼叫 gh pr create 一次' c_private

run fail ok '' "${T}/bare"
c_vis_fail() { [ "${rc}" -eq 1 ] && [ "$(calls 'pr create')" -eq 0 ] && [ "$(calls 'repo view')" -eq 1 ]; }
verdict '讀不到可見度：照公開掃描、沒呼叫 gh pr create' c_vis_fail

for fx in url-issue url-pull gh-n gh-n-lower fullwidth url-upper url-www-upper double-hash; do
  run PUBLIC ok '' "${T}/${fx}"
  verdict "沒有私有擴充：內建檢查擋 ${fx}、沒呼叫 gh pr create" c_builtin
done

run PUBLIC ok '' "${T}/url-blob"
verdict '⬛ 對照：一般檔案連結與 GHz-5 不擋、照常開' c_clean
run PUBLIC ok '' "${T}/html-entity"
verdict '⬛ 對照：HTML 字元參照（&＋井號＋數字）不擋、照常開' c_clean

# 有私有擴充：內建檢查照跑，私有 pr-scan.sh 只加不取代
run PUBLIC ok "${T}/priv-pass" "${T}/bare"
verdict '有私有擴充且 pr-scan.sh 通過：內建檢查照跑、擋裸票號' c_builtin
run PUBLIC ok "${T}/priv-pass" "${T}/url-issue"
verdict '有私有擴充且 pr-scan.sh 通過：內建檢查照跑、擋 issue 網址' c_builtin

# ── 補充案例 ──
run PUBLIC ok "${T}/priv-pass" "${T}/clean"
c_priv_pass() { [ "${rc}" -eq 0 ] && [ "$(calls 'pr create')" -eq 1 ] && [ "$(calls 'pr view')" -eq 1 ]; }
verdict '有私有擴充且 pr-scan.sh 通過：呼叫 gh pr create 一次並讀回' c_priv_pass

unset GITHUB_WORKFLOW_PRIVATE_DIR; : > "${FAKE_LOG}"; bash "${S}" fake/repo main > /dev/null 2>&1; rc=$?
c_args() { [ "${rc}" -eq 64 ] && [ "$(grep -c . "${FAKE_LOG}")" -eq 0 ]; }
verdict '參數不足：rc=64、沒呼叫 gh' c_args

echo "通過 ${PASS}，失敗 ${FAILN}"
[ "${FAILN}" -eq 0 ]
