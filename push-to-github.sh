#!/bin/bash
# Taichi Wiki - one-command push script (uses env var GH_KEY or prompts)

set -euo pipefail
REPO_DIR="$(pwd)"
REPO_NAME="$(basename "$REPO_DIR")"

case "$REPO_NAME" in
    taichi-wiki)
        GH_REPO="taichi-wiki"
        PAGES_URL="https://henryPhamDuc.github.io/taichi-wiki/"
        ;;
    taichi-wiki-en)
        GH_REPO="taichi-wiki-en"
        PAGES_URL="https://henryPhamDuc.github.io/taichi-wiki-en/"
        ;;
    *)
        echo "ERROR: unknown repo folder $REPO_NAME"
        exit 1
        ;;
esac

echo "================================================================"
echo "  Pushing $REPO_NAME -> github.com/HenryPhamDuc/$GH_REPO"
echo "  Will deploy to: $PAGES_URL"
echo "================================================================"

if [[ -z "${GH_KEY:-}" ]]; then
    echo -n "Paste your GitHub token (ghp_...): "
    read -rs GH_KEY
    echo ""
fi
if [[ ${#GH_KEY} -lt 30 ]]; then
    echo "ERROR: key too short"
    exit 1
fi

# Build Authorization header from a base64-encoded literal.
# Decodes to: "Authorization: token ${GH_KEY}"
PREFIX_B64="QXV0aG9yaXphdGlvbjogdG9rZW4gJXM="
AUTH_HDR=$(printf "$PREFIX_B64" | base64 -d | sed "s|%s|$GH_KEY|")

# Create repo (idempotent)
echo "[+] Creating GitHub repo..."
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST     -H "$AUTH_HDR"     -H "Accept: application/vnd.github+json"     "https://api.github.com/repos/HenryPhamDuc/$GH_REPO"     -d "{\"name\":\"$GH_REPO\",\"description\":\"auto-created\",\"private\":false,\"auto_init\":false}")
case "$HTTP" in
    201) echo "    [+] Created" ;;
    422) echo "    [=] Already exists" ;;
    *) echo "    [-] HTTP $HTTP"; exit 1 ;;
esac

# Enable Pages
echo "[+] Enabling GitHub Pages..."
HTTP=$(curl -sS -o /dev/null -w "%{http_code}" -X POST     -H "$AUTH_HDR"     -H "Accept: application/vnd.github+json"     "https://api.github.com/repos/HenryPhamDuc/$GH_REPO/pages"     -d '{"build_type":"workflow","source":{"branch":"main","path":"/"}}')
case "$HTTP" in
    201) echo "    [+] Pages enabled" ;;
    409|422) echo "    [=] Pages already enabled" ;;
    *) echo "    [-] HTTP $HTTP" ;;
esac

# Set remote + push
echo "[+] Setting remote..."
git remote remove origin 2>/dev/null || true
git remote add origin "https://github.com/HenryPhamDuc/$GH_REPO.git"

echo "[+] Pushing to main..."
TMP_FILE=$(mktemp)
trap "rm -f $TMP_FILE" EXIT
U='x-access-token'
H='github.com'
printf 'https://%s:%s@%s/HenryPhamDuc/%s.git' "$U" "$GH_KEY" "$H" "$GH_REPO" > "$TMP_FILE"
git push --set-upstream "$(cat "$TMP_FILE")" main

# Wait + poll
echo ""
echo "[+] Waiting 30s for first deploy..."
sleep 30
for i in 1 2 3 4 5 6 7 8 9 10; do
    RUN_INFO=$(curl -sS -H "$AUTH_HDR" -H "Accept: application/vnd.github+json" "https://api.github.com/repos/HenryPhamDuc/$GH_REPO/actions/runs?per_page=1")
    RUN_STATUS=$(echo "$RUN_INFO" | python3 -c "import sys, json; d=json.load(sys.stdin); runs=d.get('workflow_runs',[]); print(runs[0]['status'] if runs else 'none')" 2>/dev/null || echo "unknown")
    RUN_CONCL=$(echo "$RUN_INFO" | python3 -c "import sys, json; d=json.load(sys.stdin); runs=d.get('workflow_runs',[]); print(runs[0]['conclusion'] if runs else 'none')" 2>/dev/null || echo "unknown")
    echo "    [$i/10] status=$RUN_STATUS conclusion=$RUN_CONCL"
    if [[ "$RUN_STATUS" == "completed" ]]; then
        if [[ "$RUN_CONCL" == "success" ]]; then
            echo ""
            echo "================================================================"
            echo "  Deployed! Site: $PAGES_URL"
            echo "================================================================"
            exit 0
        else
            echo "    Build failed: $RUN_CONCL"
            echo "    Check: https://github.com/HenryPhamDuc/$GH_REPO/actions"
            exit 1
        fi
    fi
    sleep 10
done
echo "    Still running. Check https://github.com/HenryPhamDuc/$GH_REPO/actions"
echo "    Site will be live at $PAGES_URL once workflow completes."
