#!/bin/bash

set -e

BIGIP_USER="admin"
BIGIP_PASS="ilovesleep"

DOWNLOAD_DIR="/var/config/rest/downloads"
REPO_API="https://api.github.com/repos/F5Networks/f5-declarative-onboarding/releases/latest"

echo "[+] Checking required tools..."

if ! command -v curl >/dev/null 2>&1; then
  echo "[-] curl not found."
  exit 1
fi

echo "[+] Getting latest Declarative Onboarding release from GitHub..."

RELEASE_JSON="$(curl -skL "$REPO_API")"

RPM_URL="$(
  echo "$RELEASE_JSON" \
    | grep 'browser_download_url' \
    | grep 'f5-declarative-onboarding-' \
    | grep '\.noarch\.rpm' \
    | sed 's/.*"browser_download_url": "\(.*\)".*/\1/' \
    | head -n 1
)"

RPM_NAME="$(basename "$RPM_URL")"

RELEASE_TAG="$(
  echo "$RELEASE_JSON" \
    | grep '"tag_name"' \
    | head -n 1 \
    | sed 's/.*"tag_name": "\(.*\)".*/\1/'
)"

if [ -z "$RPM_URL" ]; then
  echo "[-] Could not find RPM URL from GitHub latest release."
  echo "[-] Raw GitHub response first lines:"
  echo "$RELEASE_JSON" | head -n 30
  echo
  echo "[-] Check manually:"
  echo "    https://github.com/F5Networks/f5-declarative-onboarding/releases"
  exit 1
fi

echo "[+] Latest GitHub release: $RELEASE_TAG"
echo "[+] RPM name: $RPM_NAME"
echo "[+] RPM URL: $RPM_URL"

mkdir -p "$DOWNLOAD_DIR"

echo "[+] Downloading RPM to $DOWNLOAD_DIR/$RPM_NAME ..."

curl -kL -o "$DOWNLOAD_DIR/$RPM_NAME" "$RPM_URL"

if [ ! -s "$DOWNLOAD_DIR/$RPM_NAME" ]; then
  echo "[-] Download failed or file is empty."
  exit 1
fi

echo "[+] Installing DO package using local iControl REST..."

INSTALL_PAYLOAD="{\"operation\":\"INSTALL\",\"packageFilePath\":\"$DOWNLOAD_DIR/$RPM_NAME\"}"

TASK_RESPONSE="$(curl -sku "$BIGIP_USER:$BIGIP_PASS" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$INSTALL_PAYLOAD" \
  https://localhost/mgmt/shared/iapp/package-management-tasks)"

echo "$TASK_RESPONSE"

TASK_ID="$(
  echo "$TASK_RESPONSE" \
    | sed -n 's/.*"id":"\([^"]*\)".*/\1/p'
)"

if [ -z "$TASK_ID" ]; then
  echo "[-] Could not extract task ID."
  echo "[-] Full response:"
  echo "$TASK_RESPONSE"
  exit 1
fi

echo "[+] Task ID: $TASK_ID"
echo "[+] Waiting for installation to finish..."

for i in $(seq 1 60); do
  STATUS_RESPONSE="$(curl -sku "$BIGIP_USER:$BIGIP_PASS" \
    https://localhost/mgmt/shared/iapp/package-management-tasks/$TASK_ID)"

  STATUS="$(
    echo "$STATUS_RESPONSE" \
      | sed -n 's/.*"status":"\([^"]*\)".*/\1/p'
  )"

  echo "    attempt=$i status=$STATUS"

  if [ "$STATUS" = "FINISHED" ]; then
    echo "[+] Installation finished."
    break
  fi

  if [ "$STATUS" = "FAILED" ]; then
    echo "[-] Installation failed:"
    echo "$STATUS_RESPONSE"
    exit 1
  fi

  sleep 5
done

echo "[+] Verifying DO endpoint..."

curl -sku "$BIGIP_USER:$BIGIP_PASS" \
  https://localhost/mgmt/shared/declarative-onboarding/info

echo
echo "[+] Done."
