#!/bin/bash

# ============================================================
# Breeze Radio — UFW Firewall Setup
# ============================================================
# Configures UFW rules for the streaming stack.
# Run with sudo: sudo ./setup-firewall.sh
#
# Optional: pass your studio IP to restrict source ports
#   sudo ./setup-firewall.sh --studio-ip 203.0.113.50

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "  ${BLUE}ℹ${NC}  $1"; }
success() { echo -e "  ${GREEN}✓${NC}  $1"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $1"; }
error()   { echo -e "  ${RED}✗${NC}  $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root (sudo ./setup-firewall.sh)"
    exit 1
fi

# Check ufw
if ! command -v ufw &>/dev/null; then
    error "UFW is not installed. Install with: apt install ufw"
    exit 1
fi

# Parse arguments
STUDIO_IP=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --studio-ip)
            STUDIO_IP="$2"
            shift 2
            ;;
        *)
            echo "Usage: sudo ./setup-firewall.sh [--studio-ip <IP>]"
            exit 1
            ;;
    esac
done

echo ""
echo -e "${BOLD}Configuring UFW firewall for streaming stack${NC}"
echo ""

# Ensure SSH is allowed first (safety net)
info "Ensuring SSH access is preserved..."
ufw allow 22/tcp >/dev/null 2>&1
success "SSH (port 22) allowed"

# HTTP + HTTPS (public)
info "Opening HTTP/HTTPS for listeners and Let's Encrypt..."
ufw allow 80/tcp >/dev/null 2>&1
success "HTTP (port 80) allowed"
ufw allow 443/tcp >/dev/null 2>&1
success "HTTPS (port 443) allowed"

# Studio source ports
if [ -n "$STUDIO_IP" ]; then
    info "Restricting studio ports to ${STUDIO_IP}..."
    ufw allow from "$STUDIO_IP" to any port 8010 proto tcp >/dev/null 2>&1
    success "Port 8010 (FLAC) allowed from ${STUDIO_IP} only"
    ufw allow from "$STUDIO_IP" to any port 8011 proto tcp >/dev/null 2>&1
    success "Port 8011 (Ogg) allowed from ${STUDIO_IP} only"
else
    warn "No --studio-ip specified, opening studio ports to all IPs"
    warn "For production, re-run with: sudo ./setup-firewall.sh --studio-ip <YOUR_STUDIO_IP>"
    ufw allow 8010/tcp >/dev/null 2>&1
    success "Port 8010 (FLAC) allowed"
    ufw allow 8011/tcp >/dev/null 2>&1
    success "Port 8011 (Ogg) allowed"
fi

# Enable UFW if not already
if ufw status | grep -q "Status: inactive"; then
    echo ""
    read -rp "  → UFW is inactive. Enable it now? (Y/n): " enable_ufw
    if [[ ! "$enable_ufw" =~ ^[Nn]$ ]]; then
        ufw --force enable
        success "UFW enabled"
    else
        warn "UFW not enabled. Run 'sudo ufw enable' when ready."
    fi
else
    ufw reload >/dev/null 2>&1
    success "UFW rules reloaded"
fi

# Show status
echo ""
echo -e "${BOLD}Current UFW status:${NC}"
echo ""
ufw status numbered
echo ""
success "Firewall setup complete!"
