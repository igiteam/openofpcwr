#!/bin/bash
# ============================================
# Mumble VOIP Server - PufferPanel Template
# Installs Murmur as a PufferPanel server template
# ============================================

set -e

# Configuration
LOGO_URL="https://cdn.gitgpt.chat/rtx/images/mumble-voip-logo.png"

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎙️ Installing Mumble VOIP Server for PufferPanel..."

# ============================================
# VERIFY PUFFERPANEL
# ============================================
log "Verifying PufferPanel installation..."

if ! command -v pufferpanel &>/dev/null && [ ! -d "/var/lib/pufferpanel" ]; then
    error "PufferPanel not found. Install it first: https://docs.pufferpanel.com/"
fi

PUFFER_TEMPLATE_DIR="/etc/pufferpanel/templates"
if [ ! -d "$PUFFER_TEMPLATE_DIR" ]; then
    error "PufferPanel template directory not found at $PUFFER_TEMPLATE_DIR"
fi

info "PufferPanel detected at $PUFFER_TEMPLATE_DIR"

# ============================================
# ASK FOR MUMBLE CONFIGURATION
# ============================================
echo ""
info "📝 Mumble Server Configuration"
echo "================================"

read -p "Server name [Mumble Server]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-"Mumble Server"}

read -p "Max users [100]: " MAX_USERS
MAX_USERS=${MAX_USERS:-100}

read -p "Welcome message [Welcome to Mumble!]: " WELCOME_TEXT
WELCOME_TEXT=${WELCOME_TEXT:-"Welcome to Mumble!"}

read -p "Server password (leave empty for none): " SERVER_PASSWORD

read -s -p "SuperUser (admin) password (min 8 chars): " SUPERUSER_PASSWORD
echo ""
if [ -z "$SUPERUSER_PASSWORD" ]; then
    SUPERUSER_PASSWORD=$(openssl rand -base64 12)
    warn "Generated SuperUser password: $SUPERUSER_PASSWORD"
fi

read -p "Max bandwidth (kbit/s) [72000]: " MAX_BANDWIDTH
MAX_BANDWIDTH=${MAX_BANDWIDTH:-72000}

# ============================================
# INSTALL MUMBLE SERVER ON HOST
# ============================================
log "📦 Installing mumble-server package..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq mumble-server openssl

# Stop the default system service — PufferPanel will manage it per-instance
systemctl stop mumble-server 2>/dev/null || true
systemctl disable mumble-server 2>/dev/null || true

MURMUR_BIN=$(command -v mumble-server || command -v murmurd)
if [ -z "$MURMUR_BIN" ]; then
    error "Murmur binary not found after install"
fi
info "Murmur binary: $MURMUR_BIN"

# ============================================
# CREATE PUFFERPANEL TEMPLATE
# ============================================
log "📝 Writing PufferPanel template..."

TEMPLATE_FILE="$PUFFER_TEMPLATE_DIR/mumble.json"

cat > "$TEMPLATE_FILE" << 'TEMPLATE_EOF'
{
  "name": "Mumble VOIP Server",
  "display_name": "Mumble (Murmur)",
  "type": "mumble",
  "description": "Open source, low-latency, high-quality team voice chat server",
  "icon": "https://www.mumble.info/css/mumble-logo.png",
  "supported_architectures": ["linux/amd64", "linux/arm64"],
  "minimum_requirements": {
    "cpu": 1,
    "memory": 256,
    "disk": 512
  },
  "data": {
    "port": {
      "type": "number",
      "desc": "Voice port (TCP and UDP)",
      "display": "Voice Port",
      "required": true,
      "default": 64738
    },
    "ice_port": {
      "type": "number",
      "desc": "ICE interface port (TCP)",
      "display": "ICE Port",
      "required": true,
      "default": 6502
    },
    "server_name": {
      "type": "string",
      "desc": "Server display name",
      "display": "Server Name",
      "required": true,
      "default": "Mumble Server"
    },
    "max_users": {
      "type": "number",
      "desc": "Maximum concurrent users",
      "display": "Max Users",
      "required": true,
      "default": 100
    },
    "welcome_text": {
      "type": "string",
      "desc": "Welcome message shown to connecting clients",
      "display": "Welcome Text",
      "required": false,
      "default": "Welcome to Mumble!"
    },
    "server_password": {
      "type": "string",
      "desc": "Password required to join (leave empty for none)",
      "display": "Server Password",
      "required": false,
      "default": ""
    },
    "superuser_password": {
      "type": "string",
      "desc": "SuperUser (admin) password",
      "display": "SuperUser Password",
      "required": true,
      "default": ""
    },
    "max_bandwidth": {
      "type": "number",
      "desc": "Maximum bandwidth in kbit/s",
      "display": "Max Bandwidth (kbit/s)",
      "required": true,
      "default": 72000
    }
  },
  "environment": {
    "MURMUR_PORT": "${port}",
    "MURMUR_ICE_PORT": "${ice_port}",
    "MURMUR_SERVER_NAME": "${server_name}",
    "MURMUR_MAX_USERS": "${max_users}",
    "MURMUR_WELCOME": "${welcome_text}",
    "MURMUR_PASSWORD": "${server_password}",
    "MURMUR_SUPERUSER_PASSWORD": "${superuser_password}",
    "MURMUR_BANDWIDTH": "${max_bandwidth}"
  },
  "installation": {
    "commands": [
      {
        "type": "download",
        "url": "https://raw.githubusercontent.com/mumble-voip/mumble/master/README.md",
        "target": "README.md"
      }
    ]
  },
  "run": {
    "command": "mumble-server -fg -ini ${__INSTALL_DIR__}/mumble-server.ini",
    "stop": "^C",
    "workingDirectory": "${__INSTALL_DIR__}",
    "pre": [
      {
        "command": "mkdir -p ${__INSTALL_DIR__}/data"
      },
      {
        "command": "printf 'database=%s\\nport=%s\\nice=port=%s\\nhost=%s\\nwelcometext=%s\\nusers=%s\\nbandwidth=%s\\nserverpassword=%s\\n' \"${__INSTALL_DIR__}/data/murmur.sqlite\" \"$MURMUR_PORT\" \"$MURMUR_ICE_PORT\" \"0.0.0.0\" \"$MURMUR_WELCOME\" \"$MURMUR_MAX_USERS\" \"$MURMUR_BANDWIDTH\" \"$MURMUR_PASSWORD\" > ${__INSTALL_DIR__}/mumble-server.ini"
      },
      {
        "command": "mumble-server -ini ${__INSTALL_DIR__}/mumble-server.ini -supw \"$MURMUR_SUPERUSER_PASSWORD\""
      }
    ]
  },
  "ports": {
    "voice": {
      "port": "${port}",
      "protocol": "udp"
    },
    "voice_tcp": {
      "port": "${port}",
      "protocol": "tcp"
    },
    "ice": {
      "port": "${ice_port}",
      "protocol": "tcp"
    }
  }
}
TEMPLATE_EOF

success "✅ Template written to $TEMPLATE_FILE"

# ============================================
# VALIDATE JSON
# ============================================
if command -v jq &>/dev/null; then
    if jq empty "$TEMPLATE_FILE" 2>/dev/null; then
        info "✅ Template JSON is valid"
    else
        error "Template JSON is invalid — check $TEMPLATE_FILE"
    fi
else
    warn "jq not installed — skipping JSON validation"
fi

# ============================================
# RELOAD PUFFERPANEL
# ============================================
log "🔄 Reloading PufferPanel..."

if systemctl is-active --quiet pufferpanel; then
    systemctl restart pufferpanel
    success "PufferPanel restarted"
else
    warn "PufferPanel service not active — restart manually after install"
fi

# ============================================
# FINAL OUTPUT
# ============================================
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         MUMBLE VOIP TEMPLATE INSTALLED IN PUFFERPANEL          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Mumble template installed!"
echo ""
info "📋 Next steps in the PufferPanel web UI:"
info "   1. Log in to PufferPanel"
info "   2. Create New Server"
info "   3. Choose template: Mumble VOIP Server"
info "   4. Fill in the variables (server name, ports, passwords)"
info "   5. Deploy"
echo ""
info "🔑 Default SuperUser password (if you left it empty):"
info "   $SUPERUSER_PASSWORD"
echo ""
info "📁 Template location:"
info "   $TEMPLATE_FILE"
echo ""
info "🎯 Voice port: TCP + UDP must both be open on your firewall"
info "🎯 ICE port: TCP only, used for admin/management if you enable ICE"
echo ""
warn "This installs the mumble-server package system-wide."
warn "PufferPanel manages each instance separately via its own .ini file."
echo ""