#!/bin/bash

# =============================================================
#   Supabase Self-Host Deployment Script
#   Repo   : https://github.com/PriyanshuValiya/supabase-selfhost
#   Target : Ubuntu 20.04 / 22.04 / 24.04 (AWS EC2)
#   Usage  : chmod +x shellscript.sh && ./shellscript.sh
#
#   Steps:
#     0.  Validates OS, RAM & disk space
#     1.  Refreshes package lists (no upgrade — prevents hangs)
#     2.  Installs required dependencies
#     3.  Adds 4 GB swap (prevents OOM kills)
#     4.  Installs Docker via official repo
#     5.  Installs latest Docker Compose
#     6.  Clones Supabase repository
#     7.  Auto-generates secrets & configures .env
#     8.  Pulls Docker images & starts all services
#     9.  Health check + prints full summary
# =============================================================

set -euo pipefail
IFS=$'\n\t'

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[✔] $1${NC}"; }
warn()    { echo -e "${YELLOW}[⚠] $1${NC}"; }
error()   { echo -e "${RED}[✘] $1${NC}"; exit 1; }
info()    { echo -e "${CYAN}[➜] $1${NC}"; }
section() {
  echo ""
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}${BOLD}  $1${NC}"
  echo -e "${CYAN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ── Suppress ALL interactive prompts globally ─────────────────
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# ── Banner ────────────────────────────────────────────────────
print_banner() {
  echo -e "${CYAN}${BOLD}"
  echo "  ███████╗██╗   ██╗██████╗  █████╗ ██████╗  █████╗ ███████╗███████╗"
  echo "  ██╔════╝██║   ██║██╔══██╗██╔══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝"
  echo "  ███████╗██║   ██║██████╔╝███████║██████╔╝███████║███████╗█████╗  "
  echo "  ╚════██║██║   ██║██╔═══╝ ██╔══██║██╔══██╗██╔══██║╚════██║██╔══╝  "
  echo "  ███████║╚██████╔╝██║     ██║  ██║██████╔╝██║  ██║███████║███████╗"
  echo "  ╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}Ubuntu 20.04 / 22.04 / 24.04  —  AWS EC2 Edition${NC}"
  echo -e "  ${YELLOW}Hang-free  •  Swap-safe  •  Reconnect-resilient${NC}"
  echo -e "  ${CYAN}github.com/PriyanshuValiya/supabase-selfhost${NC}"
  echo ""
}

# ── Step 0: Validate OS, RAM & Disk ──────────────────────────
validate_system() {
  section "Step 0: Validating System Requirements"

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=${VERSION_ID:-"unknown"}
  else
    error "Cannot detect OS. /etc/os-release not found."
  fi

  [[ "$OS" != "ubuntu" ]] && \
    error "Unsupported OS: $OS. This script requires Ubuntu 20.04 / 22.04 / 24.04."

  case "$VERSION_ID" in
    20.04|22.04|24.04) log "OS: Ubuntu $VERSION_ID ✓" ;;
    *) warn "Ubuntu $VERSION_ID is untested. Proceeding anyway..." ;;
  esac

  # RAM check
  TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  TOTAL_RAM_MB=$((TOTAL_RAM_KB / 1024))
  if (( TOTAL_RAM_MB < 3500 )); then
    warn "Low RAM: ${TOTAL_RAM_MB} MB. Supabase recommends 4 GB+."
    warn "Swap will be added. Upgrade to t3.medium or larger for best results."
  else
    log "RAM: ${TOTAL_RAM_MB} MB ✓"
  fi

  # Disk check
  FREE_DISK_GB=$(df -BG / | awk 'NR==2{gsub("G",""); print $4}')
  if (( FREE_DISK_GB < 15 )); then
    error "Insufficient disk: ${FREE_DISK_GB} GB free. Need at least 15 GB."
  else
    log "Disk: ${FREE_DISK_GB} GB free ✓"
  fi

  # Must NOT be root
  if [ "$EUID" -eq 0 ]; then
    error "Do NOT run as root. Use the 'ubuntu' user with sudo access."
  fi

  log "User: $(whoami) ✓"
}

# ── Step 1: Package List Update (NO upgrade) ─────────────────
update_packages() {
  section "Step 1: Refreshing Package Lists"
  info "Running apt-get update only — skipping upgrade to prevent kernel restart hangs."

  if dpkg -l 2>/dev/null | grep -q needrestart; then
    sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" \
      /etc/needrestart/needrestart.conf 2>/dev/null || true
  fi

  sudo apt-get update -y -q
  log "Package lists refreshed."
}

# ── Step 2: Install Dependencies ─────────────────────────────
install_dependencies() {
  section "Step 2: Installing System Dependencies"

  sudo apt-get install -y -q \
    git \
    curl \
    wget \
    unzip \
    tar \
    openssl \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    htop \
    screen

  log "All dependencies installed."
}

# ── Step 3: Swap Space ────────────────────────────────────────
setup_swap() {
  section "Step 3: Configuring 4 GB Swap Space"

  SWAPFILE="/swapfile"

  if swapon --show | grep -q "$SWAPFILE" 2>/dev/null; then
    warn "Swap already active at $SWAPFILE. Skipping."
    free -h
    return
  fi

  if [ -f "$SWAPFILE" ]; then
    warn "$SWAPFILE exists but inactive. Re-enabling..."
    sudo swapon "$SWAPFILE"
  else
    info "Allocating 4 GB swapfile..."
    sudo fallocate -l 4G "$SWAPFILE"
    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
    sudo swapon "$SWAPFILE"

    if ! grep -q "$SWAPFILE" /etc/fstab; then
      echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
  fi

  # Use swap only as a safety net, not aggressively
  sudo sysctl vm.swappiness=10 > /dev/null
  if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf > /dev/null
  fi

  log "Swap configured: $(free -h | grep Swap)"
}

# ── Step 4: Install Docker ────────────────────────────────────
install_docker() {
  section "Step 4: Installing Docker (Official Repo)"

  if command -v docker &>/dev/null; then
    warn "Docker already installed: $(docker --version). Skipping."
    return
  fi

  info "Adding Docker GPG key..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  info "Adding Docker apt repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt-get update -y -q

  info "Installing Docker packages..."
  sudo apt-get install -y -q \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin

  sudo systemctl start docker
  sudo systemctl enable docker
  sudo usermod -aG docker "$USER"

  log "Docker installed: $(docker --version)"
}

# ── Step 5: Install Docker Compose ───────────────────────────
install_docker_compose() {
  section "Step 5: Installing Docker Compose"

  if command -v docker-compose &>/dev/null; then
    warn "Docker Compose already installed: $(docker-compose --version). Skipping."
    return
  fi

  info "Fetching latest Docker Compose release..."
  COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
    | grep '"tag_name"' | cut -d'"' -f4)

  [[ -z "$COMPOSE_VERSION" ]] && \
    error "Failed to fetch Docker Compose version. Check your internet connection."

  info "Downloading Docker Compose $COMPOSE_VERSION..."
  sudo curl -fsSL \
    "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose

  sudo chmod +x /usr/local/bin/docker-compose
  sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

  log "Docker Compose installed: $(docker-compose --version)"
}

# ── Step 6: Clone Supabase ────────────────────────────────────
clone_supabase() {
  section "Step 6: Cloning Supabase Repository"

  SUPABASE_DIR="$HOME/supabase"

  if [ -d "$SUPABASE_DIR/.git" ]; then
    warn "Supabase repo already exists. Pulling latest..."
    cd "$SUPABASE_DIR"
    git pull --ff-only 2>/dev/null || warn "Could not pull latest. Continuing with existing version."
  else
    info "Cloning Supabase (shallow clone for speed)..."
    git clone --depth 1 https://github.com/supabase/supabase "$SUPABASE_DIR"
  fi

  log "Supabase repo ready: $SUPABASE_DIR"
}

# ── Step 7: Configure .env ────────────────────────────────────
configure_env() {
  section "Step 7: Generating Secrets & Configuring .env"

  DOCKER_DIR="$HOME/supabase/docker"
  cd "$DOCKER_DIR"

  [[ ! -f ".env.example" ]] && \
    error ".env.example not found in $DOCKER_DIR — clone may be incomplete."

  if [ ! -f ".env" ]; then
    cp .env.example .env
    log "Copied .env.example → .env"
  else
    warn ".env already exists — updating secrets in place."
  fi

  # Generate cryptographically secure secrets
  JWT_SECRET=$(openssl rand -base64 48 | tr -d '\n/+=' | cut -c1-40)
  POSTGRES_PASSWORD=$(openssl rand -base64 32 | tr -d '\n/+=' | cut -c1-24)
  DASHBOARD_PASSWORD=$(openssl rand -base64 24 | tr -d '\n/+=' | cut -c1-16)

  # Resolve public IP — EC2 metadata first, then fallback
  PUBLIC_IP=$(curl -sf --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 \
    || curl -sf --max-time 5 http://checkip.amazonaws.com \
    || echo "localhost")
  PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')

  info "Public IP detected: $PUBLIC_IP"

  # Inject into .env
  sed -i "s|^JWT_SECRET=.*|JWT_SECRET=${JWT_SECRET}|"                         .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${POSTGRES_PASSWORD}|"     .env
  sed -i "s|^DASHBOARD_PASSWORD=.*|DASHBOARD_PASSWORD=${DASHBOARD_PASSWORD}|" .env
  sed -i "s|^SITE_URL=.*|SITE_URL=http://${PUBLIC_IP}:8000|"                   .env
  sed -i "s|^API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://${PUBLIC_IP}:8000|"   .env

  # Save credentials + cheat-sheet
  CREDS_FILE="$HOME/supabase-credentials.txt"
  cat > "$CREDS_FILE" <<EOF
╔══════════════════════════════════════════════════════════╗
║         SUPABASE CREDENTIALS — KEEP THIS SAFE!           ║
║               Generated: $(date)
╚══════════════════════════════════════════════════════════╝

  Dashboard URL      : http://${PUBLIC_IP}:8000
  Dashboard Username : supabase
  Dashboard Password : ${DASHBOARD_PASSWORD}

  Postgres Password  : ${POSTGRES_PASSWORD}
  JWT Secret         : ${JWT_SECRET}

  .env Location      : ${DOCKER_DIR}/.env
  Compose Directory  : ${DOCKER_DIR}

══════════════════════════════════════════════════════════
  QUICK COMMANDS
══════════════════════════════════════════════════════════

  View logs          :  cd ~/supabase/docker && docker-compose logs -f
  View service log   :  cd ~/supabase/docker && docker-compose logs -f <service>
  Stop everything    :  cd ~/supabase/docker && docker-compose down
  Start everything   :  cd ~/supabase/docker && docker-compose up -d
  Restart a service  :  cd ~/supabase/docker && docker-compose restart <service>
  Container status   :  cd ~/supabase/docker && docker-compose ps
  Memory + CPU       :  docker stats --no-stream
  Free memory        :  free -h

══════════════════════════════════════════════════════════
EOF

  chmod 600 "$CREDS_FILE"
  log "Credentials saved to: $CREDS_FILE"
}

# ── Step 8: Pull Images & Start Supabase ─────────────────────
start_supabase() {
  section "Step 8: Pulling Docker Images & Starting Supabase"

  cd "$HOME/supabase/docker"

  if docker ps &>/dev/null 2>&1; then
    DOCKER_CMD="docker-compose"
  else
    warn "Docker group not active in this session. Using sudo (normal on first run)."
    DOCKER_CMD="sudo docker-compose"
  fi

  info "Pulling all Supabase images — this takes 5–10 min on first run..."
  $DOCKER_CMD pull

  info "Starting all services in detached mode..."
  $DOCKER_CMD up -d --remove-orphans

  log "All Supabase containers started."
}

# ── Step 9: Health Check & Summary ───────────────────────────
health_check() {
  section "Step 9: Health Check & Deployment Summary"

  cd "$HOME/supabase/docker"

  if docker ps &>/dev/null 2>&1; then
    DOCKER_CMD="docker-compose"
  else
    DOCKER_CMD="sudo docker-compose"
  fi

  info "Waiting 20 seconds for services to initialize..."
  sleep 20

  echo ""
  info "Container status:"
  echo ""
  $DOCKER_CMD ps
  echo ""

  info "Testing API gateway on port 8000..."
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 http://localhost:8000 || echo "000")

  if [[ "$HTTP_STATUS" =~ ^(200|301|302)$ ]]; then
    log "API gateway responding (HTTP $HTTP_STATUS) ✓"
  else
    warn "API gateway returned HTTP $HTTP_STATUS — services may still be warming up."
    warn "Wait 30 more seconds then test: curl -I http://localhost:8000"
  fi

  PUBLIC_IP=$(curl -sf --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 \
    || curl -sf --max-time 5 http://checkip.amazonaws.com \
    || echo "localhost")
  PUBLIC_IP=$(echo "$PUBLIC_IP" | tr -d '[:space:]')

  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════════════════════╗"
  echo "  ║        🚀  SUPABASE DEPLOYED SUCCESSFULLY!  🚀           ║"
  echo "  ╠══════════════════════════════════════════════════════════╣"
  echo "  ║                                                          ║"
  printf "  ║  %-12s →  http://%-34s\n" "Dashboard"  "${PUBLIC_IP}:8000 ║"
  printf "  ║  %-12s →  http://%-34s\n" "REST API"   "${PUBLIC_IP}:8000/rest/v1/ ║"
  printf "  ║  %-12s →  http://%-34s\n" "Auth API"   "${PUBLIC_IP}:8000/auth/v1/ ║"
  printf "  ║  %-12s →  http://%-34s\n" "Storage"    "${PUBLIC_IP}:8000/storage/v1/ ║"
  printf "  ║  %-12s →  http://%-34s\n" "Realtime"   "${PUBLIC_IP}:8000/realtime/v1/ ║"
  echo "  ║                                                          ║"
  echo "  ║  Credentials  →  ~/supabase-credentials.txt             ║"
  echo "  ║                                                          ║"
  echo "  ╚══════════════════════════════════════════════════════════╝"
  echo -e "${NC}"

  echo -e "${YELLOW}${BOLD}  POST-DEPLOYMENT CHECKLIST:${NC}"
  echo -e "${YELLOW}  ❶  EC2 Security Group : port 8000 open to 0.0.0.0/0${NC}"
  echo -e "${YELLOW}  ❷  View credentials   : cat ~/supabase-credentials.txt${NC}"
  echo -e "${YELLOW}  ❸  Apply docker group : newgrp docker  (or re-login via SSH)${NC}"
  echo -e "${YELLOW}  ❹  For production     : add HTTPS via Nginx + Let's Encrypt${NC}"
  echo ""
  log "Setup complete. Enjoy Supabase! 🎉"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────
main() {
  print_banner
  validate_system
  update_packages
  install_dependencies
  setup_swap
  install_docker
  install_docker_compose
  clone_supabase
  configure_env
  start_supabase
  health_check
}

main
