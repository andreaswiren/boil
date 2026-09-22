#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
trap 'echo "[SignZone] installation failed at line $LINENO" >&2' ERR

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo ./install.sh" >&2; exit 1; }
[[ -r /etc/os-release ]] || { echo "Cannot identify OS" >&2; exit 1; }
. /etc/os-release
[[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] || { echo "SignZone boilerplate supports Debian 13 (Trixie) only." >&2; exit 1; }

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in amd64|arm64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "[SignZone] Installing build/runtime dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl openssl nginx postgresql postgresql-client \
  pcscd opensc libccid osslsigncode nftables auditd apparmor apparmor-utils \
  build-essential pkg-config libssl-dev git jq rustc cargo nodejs npm

getent group signzone >/dev/null || groupadd --system signzone
for u in signzone-web signzone-signer; do id "$u" >/dev/null 2>&1 || useradd --system --home /nonexistent --shell /usr/sbin/nologin --gid signzone "$u"; done
install -d -m 0750 -o root -g signzone /etc/signzone /etc/signzone/tls /opt/signzone/releases /var/lib/signzone/{artifacts,wrapped-keys,backups,state} /run/signzone

if [[ ! -f /etc/signzone/tls/server.key ]]; then
  openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days 30 \
    -subj "/CN=SignZone Bootstrap" -keyout /etc/signzone/tls/server.key -out /etc/signzone/tls/server.crt >/dev/null 2>&1
  chmod 0600 /etc/signzone/tls/server.key
fi
TLS_FP="$(openssl x509 -in /etc/signzone/tls/server.crt -noout -fingerprint -sha256 | cut -d= -f2)"

if [[ ! -f /etc/signzone/setup.token ]]; then
  openssl rand -base64 36 | tr -d '\n' > /etc/signzone/setup.token
  chmod 0600 /etc/signzone/setup.token
fi
SETUP_TOKEN="$(cat /etc/signzone/setup.token)"

if ! command -v node >/dev/null || [[ "$(node -p 'Number(process.versions.node.split(`.`)[0])')" -lt 20 ]]; then
  echo "[SignZone] Debian Node.js is too old for the selected Next.js baseline." >&2
  echo "Install a supported Node.js LTS from your approved repository, then rerun install.sh." >&2
  exit 1
fi

echo "[SignZone] Building web application"
cd "$ROOT_DIR"
npm install --no-audit --no-fund
npm run build

echo "[SignZone] Building Rust services"
cargo build --release --manifest-path services/Cargo.toml

VERSION="0.1.0-$(date -u +%Y%m%d%H%M%S)"
RELEASE="/opt/signzone/releases/$VERSION"
install -d -m 0755 "$RELEASE"
cp -a .next/standalone/. "$RELEASE/"
mkdir -p "$RELEASE/.next"
cp -a .next/static "$RELEASE/.next/static"
cp -a public "$RELEASE/public"
ln -sfn "$RELEASE" /opt/signzone/current
install -m 0755 services/target/release/signzone-signerd /usr/local/libexec/signzone-signerd
install -m 0755 services/target/release/signzone-osd /usr/local/libexec/signzone-osd
install -m 0755 services/target/release/signzone-dcui /usr/local/libexec/signzone-dcui

if [[ ! -f /etc/signzone/signzone.env ]]; then
  DB_PASS="$(openssl rand -base64 36 | tr -d '\n')"
  cat > /etc/signzone/signzone.env <<EOF
NODE_ENV=production
PORT=3000
HOSTNAME=127.0.0.1
DATABASE_URL=postgresql://signzone:${DB_PASS}@127.0.0.1:5432/signzone
SIGNZONE_SETUP_MODE=1
SIGNZONE_SIGNER_SOCKET=/run/signzone/signerd.sock
SIGNZONE_OSD_SOCKET=/run/signzone/osd.sock
EOF
  chmod 0600 /etc/signzone/signzone.env
  if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='signzone'" | grep -q 1; then runuser -u postgres -- psql -v ON_ERROR_STOP=1 -c "CREATE ROLE signzone LOGIN PASSWORD '${DB_PASS//\'/\'\'}';"; fi
  if ! runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='signzone'" | grep -q 1; then runuser -u postgres -- createdb -O signzone signzone; fi
fi

install -m 0644 systemd/signzone-*.service /etc/systemd/system/
install -m 0644 packaging/nginx/signzone.conf /etc/nginx/sites-available/signzone
ln -sfn /etc/nginx/sites-available/signzone /etc/nginx/sites-enabled/signzone
rm -f /etc/nginx/sites-enabled/default
install -m 0755 packaging/nftables/signzone.nft /etc/nftables.conf
nginx -t
systemctl daemon-reload
systemctl enable --now pcscd postgresql nftables nginx signzone-signerd signzone-osd signzone-web signzone-dcui

IP="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')"
[[ -n "$IP" ]] || IP="<management-ip>"
echo
echo "SignZone bootstrap is running."
echo "Setup URL: https://${IP}/setup"
echo "One-time setup token: ${SETUP_TOKEN}"
echo "Bootstrap TLS SHA256 fingerprint: ${TLS_FP}"
echo "After initialization, SignZone must delete /etc/signzone/setup.token and permanently disable setup mode."
