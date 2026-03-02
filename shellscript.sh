#!/bin/bash

# =============================================================
#   Supabase Self-Host Deployment Script
#   Target: Amazon Linux 2 / Amazon Linux 2023 (AMI)
#   Usage:  chmod +x deploy-supabase.sh && ./deploy-supabase.sh
# =============================================================

set -e  # Exit immediately on error

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()     { echo -e "${GREEN}[✔] $1${NC}"; }
warn()    { echo -e "${YELLOW}[⚠] $1${NC}"; }
error()   { echo -e "${RED}[✘] $1${NC}"; exit 1; }
section() { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${CYAN}  $1${NC}"; echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ── Detect Amazon Linux Version ───────────────────────────────
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
  else
    error "Cannot detect OS. Exiting."
  fi

  if [[ "$OS" == "amzn" && "$VERSION" == "2" ]]; then
    PKG_MANAGER="yum"
    log "Detected: Amazon Linux 2"
  elif [[ "$OS" == "amzn" && "$VERSION" == "2023" ]]; then
    PKG_MANAGER="dnf"
    log "Detected: Amazon Linux 2023"
  else
    error "Unsupported OS: $OS $VERSION. This script supports Amazon Linux 2 and 2023 only."
  fi
}

# ── Step 1: System Update ─────────────────────────────────────
update_system() {
  section "Step 1: Updating System Packages"
  sudo $PKG_MANAGER update -y

  # Amazon Linux 2023 ships with curl-minimal which conflicts with full curl.
  # curl-minimal is fully sufficient for our use — skip installing curl.
  if [[ "$PKG_MANAGER" == "dnf" ]]; then
    sudo $PKG_MANAGER install -y git wget unzip tar
  else
    sudo $PKG_MANAGER install -y git curl wget unzip tar
  fi

  log "System updated."
}

# ── Step 2: Install Docker ────────────────────────────────────
install_docker() {
  section "Step 2: Installing Docker"

  if command -v docker &>/dev/null; then
    warn "Docker already installed: $(docker --version). Skipping."
    return
  fi

  if [[ "$PKG_MANAGER" == "yum" ]]; then
    # Amazon Linux 2
    sudo amazon-linux-extras enable docker
    sudo yum install -y docker
  else
    # Amazon Linux 2023
    sudo dnf install -y docker
  fi

  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker $USER
  log "Docker installed and started: $(docker --version)"
}

# ── Step 3: Install Docker Compose ───────────────────────────
install_docker_compose() {
  section "Step 3: Installing Docker Compose"

  if command -v docker-compose &>/dev/null; then
    warn "Docker Compose already installed: $(docker-compose --version). Skipping."
    return
  fi

  COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
  sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

  log "Docker Compose installed: $(docker-compose --version)"
}

# ── Step 4: Clone Supabase ────────────────────────────────────
clone_supabase() {
  section "Step 4: Cloning Supabase Repository"

  SUPABASE_DIR="$HOME/supabase"

  if [ -d "$SUPABASE_DIR" ]; then
    warn "Supabase directory already exists at $SUPABASE_DIR. Pulling latest..."
    cd "$SUPABASE_DIR" && git pull
  else
    git clone --depth 1 https://github.com/supabase/supabase "$SUPABASE_DIR"
    log "Supabase cloned to $SUPABASE_DIR"
  fi

  cd "$SUPABASE_DIR/docker"
}

# ── Step 5: Configure .env ────────────────────────────────────
configure_env() {
  section "Step 5: Configuring .env File"

  DOCKER_DIR="$HOME/supabase/docker"
  cd "$DOCKER_DIR"

  if [ ! -f ".env" ]; then
    cp .env.example .env
    log "Copied .env.example → .env"
  else
    warn ".env already exists. Skipping copy."
  fi

  # Auto-generate secrets
  JWT_SECRET=$(openssl rand -base64 40 | tr -d '\n/+=' | cut -c1-40)
  POSTGRES_PASSWORD=$(openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-24)
  DASHBOARD_PASSWORD=$(openssl rand -base64 16 | tr -d '\n/+=' | cut -c1-16)

  # Get public IP
  PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "localhost")

  # Replace values in .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|" .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|" .env
  sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}|" .env
  sed -i "s|^SITE_URL=.*|SITE_URL=http://${PUBLIC_IP}:8000|" .env
  sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${PUBLIC_IP}:8000|" .env

  log "Secrets auto-generated and .env updated."

  # Save credentials to file
  CREDS_FILE="$HOME/supabase-credentials.txt"
  cat > "$CREDS_FILE" <<EOF
========================================
  SUPABASE CREDENTIALS — KEEP SAFE!
========================================
Dashboard URL     : http://${PUBLIC_IP}:8000
Dashboard User    : supabase
Dashboard Password: ${DASHBOARD_PASSWORD}
Postgres Password : ${POSTGRES_PASSWORD}
JWT Secret        : ${JWT_SECRET}
.env Location     : ${DOCKER_DIR}/.env
========================================
EOF
  chmod 600 "$CREDS_FILE"
  log "Credentials saved to: $CREDS_FILE"
}

# ── Step 6: Pull Images & Start Supabase ─────────────────────
start_supabase() {
  section "Step 6: Pulling Docker Images & Starting Supabase"

  cd "$HOME/supabase/docker"

  # Run docker with sudo if current user not yet in docker group (new session needed)
  DOCKER_CMD="docker-compose"
  if ! docker ps &>/dev/null; then
    warn "Docker group not active yet for current session. Using sudo."
    DOCKER_CMD="sudo docker-compose"
  fi

  $DOCKER_CMD pull
  $DOCKER_CMD up -d

  log "Supabase containers started."
}

# ── Step 7: Health Check ──────────────────────────────────────
health_check() {
  section "Step 7: Health Check"

  echo "Waiting 15 seconds for services to initialize..."
  sleep 15

  DOCKER_CMD="docker-compose"
  if ! docker ps &>/dev/null; then
    DOCKER_CMD="sudo docker-compose"
  fi

  cd "$HOME/supabase/docker"
  $DOCKER_CMD ps

  PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "localhost")

  echo ""
  log "Supabase is deployed! 🚀"
  echo -e "${CYAN}"
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │           SUPABASE DEPLOYMENT SUMMARY               │"
  echo "  ├─────────────────────────────────────────────────────┤"
  echo "  │  Dashboard  :  http://${PUBLIC_IP}:8000            "
  echo "  │  REST API   :  http://${PUBLIC_IP}:8000/rest/v1/   "
  echo "  │  Auth API   :  http://${PUBLIC_IP}:8000/auth/v1/   "
  echo "  │  Storage    :  http://${PUBLIC_IP}:8000/storage/v1/"
  echo "  │  Credentials:  ~/supabase-credentials.txt          "
  echo "  │  .env File  :  ~/supabase/docker/.env              "
  echo "  └─────────────────────────────────────────────────────┘"
  echo -e "${NC}"
  warn "Make sure port 8000 is open in your EC2 Security Group!"
  warn "Run 'cat ~/supabase-credentials.txt' to view your credentials."
}

# ── Main ──────────────────────────────────────────────────────
main() {
  echo -e "${CYAN}"
  echo "  ███████╗██╗   ██╗██████╗  █████╗ ██████╗  █████╗ ███████╗███████╗"
  echo "  ██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝"
  echo "  ███████╗██║   ██║██████╔╝███████║██████╔╝███████║███████╗█████╗  "
  echo "  ╚════██║██║   ██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝  "
  echo "  ███████║╚██████╔╝██║     ██║  ██║██████╔╝██║  ██║███████║███████╗"
  echo "  ╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
  echo -e "${NC}"
  echo -e "  Self-Host Installer for ${YELLOW}Amazon Linux 2 / 2023${NC}"
  echo ""

  detect_os
  update_system
  install_docker
  install_docker_compose
  clone_supabase
  configure_env
  start_supabase
  health_check
}

main