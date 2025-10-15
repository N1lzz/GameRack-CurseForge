#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"  # gehe ins serverfiles-Verzeichnis

# --- Farben für Logausgabe ---
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

echo -e "${GREEN}[INFO] Starte CurseForge Server-Setup...${RESET}"

# --- Standardwerte ---
CF_API_KEY=""
CF_PROJECT_ID=""
CF_FILE_ID="latest"
JAVA_PATH="java"
SERVER_JAR="server.jar"

# --- CLI Argumente einlesen (von AMP übergeben) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key) CF_API_KEY="$2"; shift 2 ;;
    --project) CF_PROJECT_ID="$2"; shift 2 ;;
    --file) CF_FILE_ID="$2"; shift 2 ;;
    --java) JAVA_PATH="$2"; shift 2 ;;
    --jar) SERVER_JAR="$2"; shift 2 ;;
    *) echo -e "${YELLOW}[WARN] Unbekanntes Argument ignoriert: $1${RESET}"; shift ;;
  esac
done

# --- Pflicht-Checks ---
if [[ -z "${CF_API_KEY}" || -z "${CF_PROJECT_ID}" ]]; then
  echo -e "${RED}[ERROR] API-Key oder Project-ID fehlen. Bitte in AMP-Settings eintragen.${RESET}"
  exit 1
fi

API="https://api.curseforge.com/v1"
HDR=(-H "x-api-key: ${CF_API_KEY}" -H "Accept: application/json")

# --- benötigte Tools prüfen ---
for tool in curl jq unzip; do
  if ! command -v "$tool" &>/dev/null; then
    echo -e "${RED}[ERROR] '$tool' ist nicht installiert. Bitte installiere es zuerst.${RESET}"
    exit 2
  fi
done

# --- Funktionen ---
download_server_pack() {
  echo -e "${GREEN}[INFO] Lade Modpack-Daten von CurseForge...${RESET}"

  local file_id="${CF_FILE_ID}"

  if [[ "${file_id}" == "latest" ]]; then
    file_id=$(curl -s "${HDR[@]}" "${API}/mods/${CF_PROJECT_ID}/files" | jq -r '
      .data
      | map(select(.releaseType==1))
      | sort_by(.fileDate) | reverse
      | map(select(.serverPackFileId != null))[0].id')
    if [[ -z "${file_id}" || "${file_id}" == "null" ]]; then
      echo -e "${RED}[ERROR] Kein ServerPack für dieses Modpack gefunden.${RESET}"
      exit 3
    fi
    echo -e "${GREEN}[INFO] Verwende neueste File-ID: ${file_id}${RESET}"
  fi

  local serverpack_id
  serverpack_id=$(curl -s "${HDR[@]}" "${API}/mods/${CF_PROJECT_ID}/files/${file_id}" | jq -r '.data.serverPackFileId')
  if [[ -z "${serverpack_id}" || "${serverpack_id}" == "null" ]]; then
    echo -e "${RED}[ERROR] Diese Version enthält kein ServerPack (serverPackFileId fehlt).${RESET}"
    exit 4
  fi

  local url
  url=$(curl -s "${HDR[@]}" "${API}/mods/${CF_PROJECT_ID}/files/${serverpack_id}/download-url" | jq -r '.data')
  if [[ -z "${url}" || "${url}" == "null" ]]; then
    echo -e "${RED}[ERROR] Download-URL konnte nicht ermittelt werden.${RESET}"
    exit 5
  fi

  echo -e "${GREEN}[INFO] Lade ServerPack herunter...${RESET}"
  mkdir -p _downloads
  local pack="_downloads/serverpack-${serverpack_id}.zip"
  curl -L --fail -o "${pack}" "${url}"

  echo -e "${GREEN}[INFO] Entpacke ServerPack...${RESET}"
  unzip -o "${pack}" -d .
}

prepare_server() {
  echo -e "${GREEN}[INFO] Bereite Serverdateien vor...${RESET}"

  # Falls Forge/Fabric-Installer enthalten ist, ausführen
  if [[ -f "startserver.sh" ]]; then
    chmod +x startserver.sh
    ./startserver.sh || true
  fi

  # --- Nach Server-JAR suchen ---
  echo -e "${GREEN}[INFO] Suche nach Server-JAR...${RESET}"

  local jar=""
  for pattern in forge fabric server; do
    jar=$(find . -maxdepth 1 -type f -iname "*${pattern}*.jar" | head -n1 || true)
    [[ -n "${jar}" ]] && break
  done

  if [[ -z "${jar}" ]]; then
    echo -e "${RED}[ERROR] Keine passende .jar gefunden. Prüfe den ServerPack-Inhalt.${RESET}"
    echo -e "${YELLOW}[HINT] Normalerweise heißt die Datei z. B. 'forge-1.20.1-43.3.2-server.jar'.${RESET}"
    exit 6
  else
    ln -sf "$(basename "$jar")" "${SERVER_JAR}"
    echo -e "${GREEN}[INFO] Verwende $(basename "$jar") als Server-JAR.${RESET}"
  fi

  echo "eula=true" > eula.txt
}

start_server() {
  echo -e "${GREEN}[INFO] Starte Minecraft Server...${RESET}"
  exec "${JAVA_PATH}" -jar "${SERVER_JAR}" nogui
}

# --- Hauptlogik ---
if [[ ! -f ".cf_installed" ]]; then
  download_server_pack
  prepare_server
  touch .cf_installed
fi

# Falls manuell ein Update erzwungen werden soll
if [[ -f ".cf_force_update" ]]; then
  echo -e "${YELLOW}[INFO] Update-Flag erkannt – lade Modpack neu...${RESET}"
  rm -f .cf_installed .cf_force_update
  download_server_pack
  prepare_server
  touch .cf_installed
fi

start_server
