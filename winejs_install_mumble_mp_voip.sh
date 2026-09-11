#!/bin/bash
# ============================================
# Mumble VOIP Server - WineJS Installer
# Adds Team Voice Chat Server to WineJS Platform
# ============================================
# App: Mumble Server (Murmur)
# Category: Communication
# Features: Team VOIP, Low-latency voice chat, Channel management
# ============================================

MUMBLE_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/mumble-voip-logo.png"

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }

log "🎙️ Installing WineJS Mumble VOIP Server..."

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

# ============= ASK FOR MUMBLE CONFIGURATION =============
echo ""
info "📝 Mumble Server Configuration"
echo "================================"
read -p "Server name [WineJS Mumble Server]: " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-"WineJS Mumble Server"}

read -p "Max users [100]: " MAX_USERS
MAX_USERS=${MAX_USERS:-100}

read -p "Welcome message [Welcome to WineJS Mumble!]: " WELCOME_TEXT
WELCOME_TEXT=${WELCOME_TEXT:-"Welcome to WineJS Mumble!"}

read -p "Server password (leave empty for no password): " SERVER_PASSWORD

read -s -p "SuperUser (admin) password (min 8 chars): " SUPERUSER_PASSWORD
echo ""
if [ -z "$SUPERUSER_PASSWORD" ]; then
    SUPERUSER_PASSWORD=$(openssl rand -base64 12)
    warn "Generated SuperUser password: $SUPERUSER_PASSWORD"
fi

read -p "Max bandwidth (kbit/s) [72000]: " MAX_BANDWIDTH
MAX_BANDWIDTH=${MAX_BANDWIDTH:-72000}

# ============= FIND NEXT AVAILABLE PORT =============
port_in_use() {
    ss -tln | grep -q ":$1 " 2>/dev/null || netstat -tln 2>/dev/null | grep -q ":$1 " || docker ps 2>/dev/null | grep -q ":$1->"
}

START_PORT=7000  # Start after PufferPanel's range (6900+)
MAX_RETRIES=50
APP_PORT=""
ICE_PORT=""

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

# Find available port for Mumble voice (TCP & UDP share same port)
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for ICE interface (optional)
for i in $(seq 1 $MAX_RETRIES); do
    TEST_PORT=$((APP_PORT + i))
    if [[ ! " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]] && ! port_in_use $TEST_PORT; then
        ICE_PORT=$TEST_PORT
        break
    fi
done

if [ -z "$APP_PORT" ]; then
    error "Could not find available port for Mumble"
fi

log "Using ports: Mumble=$APP_PORT (TCP+UDP), ICE=$ICE_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="mumble"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
DATA_DIR="/opt/winejs/data/mumble"
CONFIG_DIR="/opt/winejs/config/mumble"
ICON_DIR="/opt/winejs/translator/public/icons"

mkdir -p "$APP_DIR" "$INSTANCE_DIR" "$DATA_DIR" "$CONFIG_DIR" "$ICON_DIR"

# ============= CREATE LAUNCH SCRIPT =============
log "📝 Creating launch script..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash
cd "$(dirname "$0")/../kasmvnc-instances/mumble"
docker-compose up -d
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE DOCKER-COMPOSE.YML =============
log "📝 Creating docker-compose.yml..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Mumble VOIP Server
  winejs-mumble:
    image: mumblevoip/mumble-server:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:64738/tcp"
      - "127.0.0.1:${APP_PORT}:64738/udp"
      - "127.0.0.1:${ICE_PORT}:6502/tcp"
    environment:
      # Server configuration via environment variables
      - MUMBLE_CONFIG_BANDWIDTH=${MAX_BANDWIDTH}
      - MUMBLE_CONFIG_USERS=${MAX_USERS}
      - MUMBLE_CONFIG_WELCOMETEXT=${WELCOME_TEXT}
      - MUMBLE_CONFIG_REGISTERNAME=${SERVER_NAME}
      - MUMBLE_CONFIG_MAX_BANDWIDTH=${MAX_BANDWIDTH}
      - MUMBLE_SUPERUSER_PASSWORD=${SUPERUSER_PASSWORD}
DOCKER_EOF

# Add server password if provided
if [ -n "$SERVER_PASSWORD" ]; then
    cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
      - MUMBLE_CONFIG_SERVER_PASSWORD=${SERVER_PASSWORD}
DOCKER_EOF
fi

# Add optional settings
cat >> "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
      # Optional: Enable verbose logging if needed
      # - MUMBLE_VERBOSE=true
    volumes:
      - ${DATA_DIR}:/data
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE CONNECTION INFO PAGE =============
log "📄 Creating connection info page..."

cat > "$APP_DIR/index.html" << HTML_EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Mumble VOIP Server - WineJS</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 800px;
            width: 100%;
            overflow: hidden;
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 40px;
            text-align: center;
        }
        .header img {
            width: 80px;
            height: 80px;
            margin-bottom: 20px;
        }
        .header h1 {
            font-size: 28px;
            margin-bottom: 10px;
        }
        .header p {
            opacity: 0.9;
        }
        .content {
            padding: 40px;
        }
        .info-card {
            background: #f7f9fc;
            border-radius: 12px;
            padding: 20px;
            margin-bottom: 20px;
            border-left: 4px solid #667eea;
        }
        .info-card h3 {
            color: #333;
            margin-bottom: 15px;
            font-size: 18px;
        }
        .connection-string {
            background: #2d3748;
            color: #68d391;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 16px;
            word-break: break-all;
            margin: 10px 0;
        }
        .button {
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 12px 24px;
            border-radius: 8px;
            text-decoration: none;
            font-weight: 600;
            margin-top: 10px;
            transition: transform 0.2s, background 0.2s;
        }
        .button:hover {
            background: #5a67d8;
            transform: translateY(-2px);
        }
        .button-secondary {
            background: #48bb78;
            margin-left: 10px;
        }
        .button-secondary:hover {
            background: #38a169;
        }
        .credentials {
            background: #fff5f5;
            border-left-color: #fc8181;
        }
        .warning {
            background: #fffff0;
            border-left-color: #ed8936;
        }
        .client-list {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
            gap: 15px;
            margin-top: 20px;
        }
        .client-item {
            background: white;
            padding: 12px;
            border-radius: 8px;
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .client-item a {
            color: #667eea;
            text-decoration: none;
            font-weight: 600;
        }
        .footer {
            background: #f7f9fc;
            padding: 20px;
            text-align: center;
            color: #718096;
            font-size: 14px;
        }
        @media (max-width: 600px) {
            .content { padding: 20px; }
            .header { padding: 20px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <img src="/icons/mumble.png" alt="Mumble Logo">
            <h1>🎙️ Mumble VOIP Server</h1>
            <p>High-quality, low-latency team voice chat</p>
        </div>
        <div class="content">
            <div class="info-card">
                <h3>🔗 Connection String</h3>
                <div class="connection-string" id="connectionString">mumble://${DOMAIN_NAME}:${APP_PORT}/</div>
                <button class="button" onclick="copyConnection()">📋 Copy Connection String</button>
                <button class="button button-secondary" onclick="openMumbleClient()">🚀 Open in Mumble</button>
            </div>

            <div class="info-card">
                <h3>📱 How to Connect</h3>
                <p><strong>1. Download Mumble Client:</strong></p>
                <div class="client-list">
                    <div class="client-item"><a href="https://www.mumble.info/downloads/" target="_blank">💻 Windows/Mac/Linux</a></div>
                    <div class="client-item"><a href="https://play.google.com/store/apps/details?id=com.morlunk.mumbleclient" target="_blank">📱 Android (Plumble)</a></div>
                    <div class="client-item"><a href="https://apps.apple.com/app/mumble/id443472808" target="_blank">🍎 iOS (Mumble)</a></div>
                </div>
                <p style="margin-top: 15px;"><strong>2. Connect using:</strong></p>
                <ul style="margin-left: 20px; margin-top: 10px;">
                    <li><strong>Address:</strong> ${DOMAIN_NAME}</li>
                    <li><strong>Port:</strong> ${APP_PORT}</li>
                    <li><strong>Username:</strong> Choose any name</li>
                    ${SERVER_PASSWORD != "" ? '<li><strong>Server Password:</strong> ' + ${SERVER_PASSWORD} + '</li>' : ''}
                </ul>
            </div>

            <div class="info-card credentials">
                <h3>🔑 Administrator Access</h3>
                <p><strong>SuperUser Password:</strong> <code id="superuserPassword">${SUPERUSER_PASSWORD}</code></p>
                <button class="button" onclick="copyPassword()">📋 Copy Password</button>
                <p style="margin-top: 10px; font-size: 14px;">
                    ⚠️ Use SuperUser to manage channels, users, and server settings.<br>
                    In Mumble client: Server → Connect → Edit → Advanced → Username: SuperUser
                </p>
            </div>

            <div class="info-card warning">
                <h3>ℹ️ Important Notes</h3>
                <ul style="margin-left: 20px;">
                    <li>Mumble uses <strong>both TCP and UDP ports ${APP_PORT}</strong> - ensure your firewall allows both</li>
                    <li>For best quality, use a <strong>wired connection</strong> or strong WiFi</li>
                    <li>Configure server certificates in Mumble client for encrypted voice</li>
                    <li>Voice quality: Opus codec, up to ${MAX_BANDWIDTH} kbit/s</li>
                </ul>
            </div>
        </div>
        <div class="footer">
            Powered by WineJS Platform | Mumble Open Source VOIP
        </div>
    </div>

    <script>
        function copyConnection() {
            const conn = document.getElementById('connectionString').innerText;
            navigator.clipboard.writeText(conn);
            alert('Connection string copied!');
        }
        
        function copyPassword() {
            const pwd = document.getElementById('superuserPassword').innerText;
            navigator.clipboard.writeText(pwd);
            alert('SuperUser password copied!');
        }
        
        function openMumbleClient() {
            const conn = document.getElementById('connectionString').innerText;
            window.location.href = conn;
        }
    </script>
</body>
</html>
HTML_EOF

# ============= CREATE CONFIG.JSON (CRITICAL FOR APP REGISTRATION) =============
log "📝 Creating config.json for app registration..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Mumble VOIP Server",
    "version": "latest",
    "description": "Open source, low-latency, high-quality team voice chat server",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "",
    "icon": "/icons/mumble.png",
    "category": "Communication",
    "features": [
        "🎙️ High-quality team voice chat (Opus codec)",
        "⚡ Low latency communication",
        "🔐 Server password protection",
        "👑 SuperUser administrator access",
        "📁 Organized channel hierarchy",
        "📱 Cross-platform clients (Windows/Mac/Linux/Android/iOS)",
        "🎨 Per-user permissions system",
        "🔊 Dynamic audio quality adjustment",
        "🛡️ Encrypted voice communication",
        "📊 Up to ${MAX_USERS} concurrent users"
    ]
}
CONF_EOF

# ============= DOWNLOAD ICON =============
log "📥 Downloading Mumble icon..."
curl -L "$MUMBLE_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE HELPER SCRIPT =============
log "🔧 Creating helper script..."

cat > /usr/local/bin/winejs-mumble << EOF
#!/bin/bash
DOMAIN_NAME="${DOMAIN_NAME}"
APP_PORT=${APP_PORT}
SUPERUSER_PASSWORD="${SUPERUSER_PASSWORD}"

case "\$1" in
    status)
        docker ps | grep winejs-mumble
        ;;
    logs)
        docker logs winejs-mumble --tail 50
        ;;
    restart)
        docker restart winejs-mumble
        echo "Mumble server restarted"
        ;;
    password)
        echo "SuperUser Password: \$SUPERUSER_PASSWORD"
        ;;
    connect)
        echo "Connection string: mumble://\$DOMAIN_NAME:\$APP_PORT/"
        ;;
    users)
        echo "Showing connected users..."
        docker exec winejs-mumble murmurd -ini /data/mumble-server.ini -users
        ;;
    config)
        echo "Opening configuration directory..."
        echo "/opt/winejs/config/mumble/"
        ls -la /opt/winejs/config/mumble/
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://\${DOMAIN_NAME}/mumble/"
        else
            echo "Visit: https://\${DOMAIN_NAME}/mumble/"
        fi
        ;;
    *)
        echo "Mumble VOIP Server Manager"
        echo ""
        echo "Commands:"
        echo "  winejs-mumble open        - Open connection info page"
        echo "  winejs-mumble status      - Check server status"
        echo "  winejs-mumble logs        - View server logs"
        echo "  winejs-mumble restart     - Restart server"
        echo "  winejs-mumble password    - Show SuperUser password"
        echo "  winejs-mumble connect     - Show connection string"
        echo "  winejs-mumble users       - List connected users"
        echo "  winejs-mumble config      - Show config location"
        echo ""
        echo "Connection: mumble://\${DOMAIN_NAME}:\${APP_PORT}/"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-mumble

# ============= START CONTAINER =============
log "🚀 Starting Mumble container..."

cd "$INSTANCE_DIR"
docker-compose down 2>/dev/null
docker-compose up -d

sleep 10

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
    docker logs winejs-${APP_NAME} --tail 20
fi

# ============= WAIT FOR MUMBLE TO INITIALIZE =============
log "⏳ Waiting for Mumble to initialize..."
sleep 5

# ============= UPDATE NGINX FOR INFO PAGE =============
log "📝 Setting up nginx for Mumble info page..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Mumble routes already exist
    if ! grep -q "location /mumble" /etc/nginx/sites-available/winejs; then
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            sed -i "${LISTEN_443_LINE}i\\
    # Mumble VOIP Server Info Page\n\
    location /mumble {\n\
        alias /opt/winejs/apps/mumble/;\n\
        try_files \\\$uri \\\$uri/ /mumble/index.html;\n\
    }\n\
    \n\
    # Mumble connection info endpoint\n\
    location /mumble/info {\n\
        return 200 '{\"server\":\"${DOMAIN_NAME}\",\"port\":${APP_PORT},\"protocol\":\"mumble\"}';\n\
        add_header Content-Type application/json;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            if nginx -t; then
                systemctl reload nginx
                log "✅ Nginx updated with Mumble routes"
            else
                warn "Nginx test failed, restoring backup"
                cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
                nginx -t && systemctl reload nginx
            fi
        fi
    else
        log "Mumble routes already exist"
    fi
fi

# ============= RESTART TRANSLATOR TO REGISTER APP =============
log "🔄 Restarting WineJS translator to register app..."
pm2 restart translator 2>/dev/null || systemctl restart winejs-translator 2>/dev/null || true

sleep 3

# ============= CREATE UNINSTALL SCRIPT =============
log "🗑️ Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_mumble.sh" << 'UNINSTALL_EOF'
#!/bin/bash
log() { echo "[$(date '+%H:%M:%S')] $1"; }

log "🧹 Uninstalling Mumble VOIP Server..."

docker stop winejs-mumble 2>/dev/null
docker rm winejs-mumble 2>/dev/null

rm -rf /opt/winejs/apps/mumble
rm -rf /opt/winejs/kasmvnc-instances/mumble
rm -rf /opt/winejs/data/mumble
rm -rf /opt/winejs/config/mumble

rm -f /usr/local/bin/winejs-mumble

# Remove nginx routes
if [ -f "/etc/nginx/sites-available/winejs" ]; then
    sed -i '/# Mumble VOIP Server Info Page/,/location \/mumble\/info/d' /etc/nginx/sites-available/winejs
    sed -i '/location \/mumble {/,/^    }/d' /etc/nginx/sites-available/winejs
    nginx -t && systemctl reload nginx
fi

pm2 restart translator 2>/dev/null || true

log "✅ Mumble VOIP Server uninstalled"
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_mumble.sh"

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           MUMBLE VOIP SERVER INSTALLED ON WINEJS!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Mumble VOIP Server installed!"
echo ""
info "🌐 Connection Info Page:"
info "   • https://$DOMAIN_NAME/mumble/"
echo ""
info "🔗 Direct Connection:"
info "   • mumble://$DOMAIN_NAME:$APP_PORT/"
echo ""
info "🔑 Administrator Access:"
info "   • SuperUser Password: $SUPERUSER_PASSWORD"
if [ -n "$SERVER_PASSWORD" ]; then
    info "   • Server Password: $SERVER_PASSWORD"
fi
echo ""
info "📊 Server Configuration:"
info "   • Server Name: $SERVER_NAME"
info "   • Max Users: $MAX_USERS"
info "   • Max Bandwidth: $MAX_BANDWIDTH kbit/s"
info "   • Welcome Text: $WELCOME_TEXT"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-mumble open        # Open connection page"
info "   • winejs-mumble status      # Check server status"
info "   • winejs-mumble password    # Show SuperUser password"
info "   • winejs-mumble connect     # Show connection string"
info "   • winejs-mumble users       # List connected users"
echo ""
info "📱 Client Downloads:"
info "   • Desktop: https://www.mumble.info/downloads/"
info "   • Android: Plumble on Google Play"
info "   • iOS: Mumble on App Store"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_mumble.sh"
echo ""
success "✨ Mumble VOIP Server is ready! Visit https://$DOMAIN_NAME/mumble/ for connection info"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"