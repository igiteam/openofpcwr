#!/bin/bash
# ============================================
# WineJS PufferPanel Installer
# Adds Game Server Management Panel to WineJS Platform
# ============================================
# App: PufferPanel
# Category: Gaming
# Features: Game Server Management, CS:GO, Minecraft, SteamCMD, Docker
# ============================================

PUFFERPANEL_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/pufferpanel-icon.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🚀 Installing WineJS PufferPanel Game Server Manager..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
fi

if [ ! -f "/opt/winejs/translator/index.js" ]; then
    error "WineJS translator not found. Please install WineJS first."
fi

# Ensure winejs-net network exists
log "Checking winejs-net network..."
if ! docker network inspect winejs-net &>/dev/null; then
    docker network create winejs-net
    log "✅ winejs-net network created"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
if [ -f "/opt/winejs/translator/index.js" ]; then
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain: " DOMAIN_NAME
fi

info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR ADMIN DETAILS =============
read -p "Enter admin email: " ADMIN_EMAIL
read -s -p "Enter admin password (min 8 chars): " ADMIN_PASSWORD
echo ""

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=6901
MAX_RETRIES=50
APP_PORT=""
SFTP_PORT=""

# Get used ports from existing apps
declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            [ -n "$PORT" ] && USED_PORTS+=($PORT)
        fi
    done
fi

# Find available port for PufferPanel web
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for SFTP
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        SFTP_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ] || [ -z "$SFTP_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: PufferPanel=$APP_PORT, SFTP=$SFTP_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="pufferpanel"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/pufferpanel"
CONFIG_DIR="/opt/winejs/config/pufferpanel"
TEMPLATES_DIR="/opt/winejs/data/pufferpanel-templates"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$TEMPLATES_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/pufferpanel"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

# Generate random database password
DB_PASS=$(openssl rand -base64 16 | tr -d '=/+')

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # MySQL Database
  pufferpanel-db:
    image: mariadb:10.11
    container_name: winejs-pufferpanel-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=${DB_PASS}
      - MYSQL_DATABASE=pufferpanel
      - MYSQL_USER=pufferpanel
      - MYSQL_PASSWORD=${DB_PASS}
    volumes:
      - ${DATA_DIR}/mysql:/var/lib/mysql
    networks:
      - winejs-net
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  # PufferPanel
  winejs-pufferpanel:
    image: pufferpanel/pufferpanel:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
      - "127.0.0.1:${SFTP_PORT}:5657"
    environment:
      - PUFFERPANEL_DB_HOST=pufferpanel-db
      - PUFFERPANEL_DB_PORT=3306
      - PUFFERPANEL_DB_DATABASE=pufferpanel
      - PUFFERPANEL_DB_USERNAME=pufferpanel
      - PUFFERPANEL_DB_PASSWORD=${DB_PASS}
      - PUFFERPANEL_WEB_HOST=0.0.0.0
      - PUFFERPANEL_WEB_PORT=8080
      - PUFFERPANEL_SFTP_PORT=5657
      # CRITICAL: Set the panel URL to fix blank screen
      - PUFFERPANEL_PANEL_URL=https://${DOMAIN_NAME}/pufferpanel
    volumes:
      - ${DATA_DIR}/servers:/var/lib/pufferpanel
      - ${TEMPLATES_DIR}:/var/lib/pufferpanel/templates
      - ${DATA_DIR}/config:/etc/pufferpanel
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      pufferpanel-db:
        condition: service_healthy
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# Wait for config directory to be created by container
log "⏳ Waiting for PufferPanel to generate config..."
sleep 5

# Create PufferPanel config with correct settings (fixes blank screen)
log "📝 Creating PufferPanel configuration..."

mkdir -p "$DATA_DIR/config"
cat > "$DATA_DIR/config/config.json" << EOF
{
  "panel": {
    "database": {
      "dialect": "mysql",
      "url": "pufferpanel:${DB_PASS}@tcp(pufferpanel-db:3306)/pufferpanel"
    },
    "panel": {
      "name": "WineJS Game Server Panel",
      "url": "https://${DOMAIN_NAME}/pufferpanel"
    }
  },
  "web": {
    "host": "0.0.0.0",
    "port": 8080
  },
  "sftp": {
    "host": "0.0.0.0",
    "port": 5657
  },
  "email": {
    "provider": "debug"
  },
  "system": {
    "log-level": "info"
  }
}
EOF

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "PufferPanel Game Server Manager",
    "version": "latest",
    "description": "Manage game servers (CS:GO, Minecraft, Rust, etc.) in your browser",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/pufferpanel.png",
    "category": "Gaming",
    "features": [
        "CS:GO Dedicated Servers",
        "Minecraft Java/Bedrock",
        "Rust, ARK, Palworld",
        "SteamCMD integration",
        "Docker container support",
        "SFTP file access",
        "Server scheduling",
        "Resource monitoring"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading PufferPanel icon..."
curl -L "$PUFFERPANEL_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon"

# ============= CREATE GAME TEMPLATES =============
log "🎮 Creating game server templates..."

# CS:GO Template
cat > "$TEMPLATES_DIR/csgo.json" << 'EOF'
{
    "name": "Counter-Strike: Global Offensive",
    "description": "CS:GO Dedicated Game Server",
    "steam": {"appId": 740, "appSetConfig": true},
    "install": [{"type": "steamcmd", "appId": 740, "platform": "linux"}],
    "run": {
        "executable": "srcds_run",
        "arguments": "-game csgo -console -usercon -ip ${ip} -port ${port} +map ${map} -maxplayers ${maxplayers}",
        "stop": "quit"
    },
    "variables": [
        {"name": "Port", "env": "port", "type": "number", "default": 27015},
        {"name": "Map", "env": "map", "type": "text", "default": "de_dust2"},
        {"name": "Max Players", "env": "maxplayers", "type": "number", "default": 20}
    ]
}
EOF

# Minecraft Template
cat > "$TEMPLATES_DIR/minecraft.json" << 'EOF'
{
    "name": "Minecraft Java",
    "description": "Vanilla Minecraft Server",
    "install": [{"type": "download", "files": ["https://launcher.mojang.com/v1/objects/${version}/server.jar"]}],
    "run": {
        "executable": "java",
        "arguments": "-Xmx${memory}M -Xms${memory}M -jar server.jar nogui",
        "stop": "stop"
    },
    "variables": [
        {"name": "Version", "env": "version", "type": "text", "default": "1.20.4"},
        {"name": "Memory (MB)", "env": "memory", "type": "number", "default": 1024}
    ]
}
EOF

chown -R 1000:1000 "$TEMPLATES_DIR" 2>/dev/null || true

# ============= CREATE ADMIN SETUP SCRIPT =============
log "🔧 Creating admin setup script..."

cat > "$APP_DIR/setup-admin.sh" << 'ADMIN_EOF'
#!/bin/bash

APP_PORT="${APP_PORT}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"
DOMAIN_NAME="${DOMAIN_NAME}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "Waiting for PufferPanel to start..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}/api/health" > /dev/null 2>&1; then
        log "✅ PufferPanel is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for PufferPanel..."
    sleep 5
    attempt=$((attempt + 1))
done

log "Creating admin user..."
docker exec winejs-pufferpanel pufferpanel user add \
    --email "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" \
    --admin \
    --name Admin 2>&1

if [ $? -eq 0 ]; then
    log "✅ Admin user created successfully"
else
    log "⚠️ Admin user may already exist"
fi

log "✅ Admin setup complete. Login at: https://${DOMAIN_NAME}/pufferpanel"
ADMIN_EOF

chmod +x "$APP_DIR/setup-admin.sh"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-pufferpanel << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}

case "\$1" in
    status)
        docker ps | grep pufferpanel
        ;;
    logs)
        docker logs winejs-pufferpanel --tail 50
        ;;
    restart)
        docker restart winejs-pufferpanel
        ;;
    create-server)
        echo "Create a new game server:"
        echo "1. Login to https://\${DOMAIN_NAME}/pufferpanel/"
        echo "2. Go to Servers → Create New"
        echo "3. Choose template (CS:GO, Minecraft, etc.)"
        echo "4. Configure ports and settings"
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/pufferpanel/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/pufferpanel/"
        fi
        ;;
    *)
        echo "PufferPanel Game Server Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-pufferpanel open      - Open panel in browser"
        echo "  winejs-pufferpanel status    - Check service status"
        echo "  winejs-pufferpanel logs      - View container logs"
        echo "  winejs-pufferpanel restart   - Restart panel"
        echo "  winejs-pufferpanel create-server - Server creation guide"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-pufferpanel

# ============= START CONTAINER =============
log "🚀 Starting PufferPanel container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

sleep 15

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= SETUP ADMIN USER =============
bash "$APP_DIR/setup-admin.sh"

# ============= UPDATE NGINX CONFIG =============
log "📝 Updating nginx configuration for PufferPanel..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if PufferPanel routes already exist
    if ! grep -q "location /pufferpanel" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # PufferPanel Game Server Manager\n\
    location /pufferpanel {\n\
        rewrite ^/pufferpanel(/.*)?$ /\\\$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \\\$host;\n\
        proxy_set_header X-Real-IP \\\$remote_addr;\n\
        proxy_set_header X-Forwarded-For \\\$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \\\$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \\\$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        proxy_read_timeout 300s;\n\
        proxy_send_timeout 300s;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with PufferPanel routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    else
        log "PufferPanel routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_pufferpanel.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling PufferPanel..."

docker stop winejs-pufferpanel winejs-pufferpanel-db 2>/dev/null
docker rm winejs-pufferpanel winejs-pufferpanel-db 2>/dev/null

rm -rf /opt/winejs/apps/pufferpanel
rm -rf /opt/winejs/kasmvnc-instances/pufferpanel
rm -rf /opt/winejs/data/pufferpanel
rm -rf /opt/winejs/config/pufferpanel

rm -f /usr/local/bin/winejs-pufferpanel

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# PufferPanel Game Server Manager/,/location \/pufferpanel /d' /etc/nginx/sites-available/winejs
    sed -i '/location \/pufferpanel {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ PufferPanel uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_pufferpanel.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           PUFFERPANEL INSTALLED ON WINEJS!                     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ PufferPanel Game Server Manager installed!"
echo ""
info "🌐 Access URLs:"
info "   • Panel: https://$DOMAIN_NAME/pufferpanel/"
info "   • SFTP: port ${SFTP_PORT}"
echo ""
info "🔑 Admin Credentials:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "🎮 Game Templates Available:"
info "   • CS:GO - Counter-Strike: Global Offensive"
info "   • Minecraft - Java Edition"
echo ""
info "📁 Server Data: /opt/winejs/data/pufferpanel/servers"
info ""
info "🎯 Quick Commands:"
info "   • winejs-pufferpanel open      # Open panel"
info "   • winejs-pufferpanel status    # Check status"
info "   • winejs-pufferpanel logs      # View logs"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_pufferpanel.sh"
echo ""
success "✨ PufferPanel is ready! Visit https://$DOMAIN_NAME/pufferpanel/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"