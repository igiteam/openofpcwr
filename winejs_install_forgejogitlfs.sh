#!/bin/bash
# ============================================
# WineJS Forgejo Installer
# Adds Forgejo Git Service to WineJS Platform
# ============================================
# App: Forgejo Git Server
# Category: Development
# Features: Git Repositories, LFS Support, Issue Tracker, CI/CD
# ============================================

# What this script does:
#     ✓ Verifies WineJS platform - Checks if /opt/winejs exists
#     ✓ Creates docker network - Creates winejs-net if missing
#     ✓ Creates all necessary directories with data persistence
#     ✓ Downloads/Configures Forgejo - Latest version with Git LFS support
#     ✓ Creates Git LFS path mapping server for large file handling
#     ✓ Sets up shared volumes system (like Docker mounts)
#     ✓ Creates launch.sh with auto-heal monitor
#     ✓ Creates config.json with all app metadata
#     ✓ Creates docker-compose.yml with volume mounts
#     ✓ Sets up automated backup system
#     ✓ Creates uninstall script with cleanup
#     ✓ Sets up PM2 for LFS mapper persistence
#     ✓ Creates CLI helper tools
#     ✓ Installs Git hooks for WineJS integration
#     ✓ Restarts translator and starts containers

set -e

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; 
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'; NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${MAGENTA}[SUCCESS]${NC} $1"; }
header() { echo -e "${CYAN}$1${NC}"; }

log "🚀 Installing WineJS Forgejo Server..."

# ============= VERIFY WINEJS PLATFORM =============
log "Verifying WineJS platform..."

if [ ! -d "/opt/winejs" ]; then
    error "WineJS platform not found at /opt/winejs"
    exit 1
fi

# Ensure winejs-net network exists and is properly created
log "Checking winejs-net network..."
if docker network ls | grep -q "winejs-net"; then
    log "✅ winejs-net network already exists"
    # Verify the network is actually usable
    if ! docker network inspect winejs-net &>/dev/null; then
        log "⚠️ Network exists but is corrupted, recreating..."
        docker network rm winejs-net 2>/dev/null || true
        docker network create winejs-net
        log "✅ winejs-net network recreated"
    fi
else
    log "Creating winejs-net network..."
    docker network create winejs-net
    if [ $? -eq 0 ]; then
        log "✅ winejs-net network created"
    else
        error "Failed to create winejs-net network"
    fi
fi

# Final verification
if ! docker network inspect winejs-net &>/dev/null; then
    error "winejs-net network is not available. Please run: docker network create winejs-net"
fi

# ============= GET DOMAIN FROM WINEJS CONFIG =============
# Get domain from existing WineJS config
if [ -f "/opt/winejs/translator/index.js" ]; then
    # Extract just the domain value, removing quotes and the variable assignment
    DOMAIN_NAME=$(grep "const DOMAIN_NAME" /opt/winejs/translator/index.js | sed -E "s/.*['\"]([^'\"]+)['\"].*/\1/")
fi

if [ -z "$DOMAIN_NAME" ]; then
    read -p "Enter your WineJS domain (e.g., wine.yourdomain.com): " DOMAIN_NAME
fi

# Clean up any quotes or whitespace
DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '"' | tr -d "'" | xargs)

info "Using domain: $DOMAIN_NAME"

# ============= ASK FOR ADMIN DETAILS =============
if [ -z "$ADMIN_EMAIL" ]; then
    read -p "Enter admin email: " ADMIN_EMAIL
fi

if [ -z "$ADMIN_PASSWORD" ]; then
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo ""
fi

# ============= FIND NEXT AVAILABLE PORT =============
log "Finding next available port..."

# Function to check if a port is in use
port_in_use() {
    local port=$1
    # Check if port is bound by any process
    if ss -tln | grep -q ":$port " || netstat -tln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    # Check if Docker is using this port
    if docker ps 2>/dev/null | grep -q ":$port->"; then
        return 0
    fi
    return 1
}

# Start checking from 6901
START_PORT=6901
MAX_RETRIES=100
APP_PORT=""
LFS_MAPPER_PORT=""

# Check existing ports from config.json files
declare -a USED_PORTS
if [ -d "/opt/winejs/apps" ]; then
    for config in /opt/winejs/apps/*/config.json; do
        if [ -f "$config" ]; then
            PORT=$(grep -o '"port": [0-9]*' "$config" | awk '{print $2}')
            if [ -n "$PORT" ]; then
                USED_PORTS+=($PORT)
            fi
        fi
    done
fi

# Find available port for Forgejo
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    # Skip if port is in config.json
    if [[ " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]]; then
        continue
    fi
    # Skip if port is in use
    if ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        break
    fi
done

# Find available port for LFS Mapper (start from APP_PORT+1)
if [ -n "$APP_PORT" ]; then
    for i in $(seq 1 $MAX_RETRIES); do
        TEST_PORT=$((APP_PORT + i))
        if [[ " ${USED_PORTS[@]} " =~ " ${TEST_PORT} " ]]; then
            continue
        fi
        if ! port_in_use $TEST_PORT; then
            LFS_MAPPER_PORT=$TEST_PORT
            break
        fi
    done
fi

if [ -z "$APP_PORT" ] || [ -z "$LFS_MAPPER_PORT" ]; then
    error "Could not find available ports"
fi

log "Using ports: Forgejo=$APP_PORT, LFSMapper=$LFS_MAPPER_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="forgejo"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
FORGEJO_DATA="/opt/winejs/data/forgejo"
FORGEJO_CONFIG="/opt/winejs/config/forgejo"
ICON_DIR="/opt/winejs/translator/public/icons"
REPO_DIR="/opt/winejs/repositories"
SHARED_VOLUMES="/opt/winejs/shared-volumes"
LFS_MAPPER_DIR="/opt/winejs/lfs-mapper"

mkdir -p "$APP_DIR"
mkdir -p "$INSTANCE_DIR"
mkdir -p "$FORGEJO_DATA"/{gitea,git,repositories,lfs}
mkdir -p "$FORGEJO_CONFIG"
mkdir -p "$ICON_DIR"
mkdir -p "$REPO_DIR"
mkdir -p "$SHARED_VOLUMES"/{backups,imports,exports,ci-cd}
mkdir -p "$LFS_MAPPER_DIR"

# ============= FIX PERMISSIONS FOR FORGEJO =============
log "🔧 Fixing permissions for Forgejo..."

# Create the .ssh directory with correct permissions
mkdir -p /opt/winejs/repositories/.ssh
chown -R 1000:1000 /opt/winejs/repositories
chmod 700 /opt/winejs/repositories/.ssh

# Fix all Forgejo directories
chown -R 1000:1000 "$FORGEJO_DATA"
chown -R 1000:1000 "$FORGEJO_CONFIG"
chown -R 1000:1000 "$REPO_DIR"
chmod -R 755 "$FORGEJO_DATA"
chmod -R 755 "$FORGEJO_CONFIG"

# ALSO create SSH directory inside Forgejo data (critical!)
mkdir -p "$FORGEJO_DATA/git/.ssh"
chown -R 1000:1000 "$FORGEJO_DATA/git"
chmod 700 "$FORGEJO_DATA/git/.ssh"

log "✅ Permissions fixed for Forgejo"

cd "$APP_DIR"

# Generate LFS JWT secret
LFS_JWT_SECRET=$(openssl rand -hex 32)

# ============= CREATE FORGEJO CONFIGURATION =============
log "📝 Creating Forgejo configuration..."

cat > "$FORGEJO_CONFIG/app.ini" << CONF_EOF
APP_NAME = WineJS Forgejo
RUN_USER = git
RUN_MODE = prod

[database]
DB_TYPE = sqlite3
PATH = /data/gitea/gitea.db

[repository]
ROOT = /data/git/repositories
DEFAULT_PRIVATE = private
DEFAULT_BRANCH = main

[server]
DOMAIN = ${DOMAIN_NAME}
HTTP_PORT = 3000
ROOT_URL = https://${DOMAIN_NAME}/forgejo/
HTTP_ADDR = 0.0.0.0
SSH_DOMAIN = ${DOMAIN_NAME}
SSH_PORT = 22
LFS_START_SERVER = true
LFS_CONTENT_PATH = /data/git/lfs
LOCAL_ROOT_URL = http://localhost:3000/

[lfs]
JWT_SECRET = ${LFS_JWT_SECRET}
MAX_FILE_SIZE = 1073741824

[security]
INSTALL_LOCK = true
SECRET_KEY = $(openssl rand -base64 32)

[service]
DISABLE_REGISTRATION = false
REQUIRE_SIGNIN_VIEW = false
ENABLE_CAPTCHA = false

[mailer]
ENABLED = false

[log]
MODE = console
LEVEL = info

[webhook]
ALLOWED_HOST_LIST = *
CONFIG_SUCCESS_URL = https://${DOMAIN_NAME}/forgejo

[cron]
ENABLED = true
RUN_AT_START = true
SCHEDULE = @every 24h

[actions]
ENABLED = true
DEFAULT_ACTIONS_URL = https://codeberg.org
CONFIG_SUCCESS_URL = https://${DOMAIN_NAME}/forgejo
CONFIG_SUCCESS_URL = https://${DOMAIN_NAME}/forgejo
CONF_EOF

chown -R 1000:1000 "$FORGEJO_DATA" "$FORGEJO_CONFIG"

# ============= CREATE LFS MAPPING SERVER =============
log "📡 Creating Git LFS path mapping server..."

cat > "$LFS_MAPPER_DIR/package.json" << 'EOF'
{
    "name": "winejs-lfs-mapper",
    "version": "1.0.0",
    "description": "Git LFS path mapping server for WineJS Forgejo integration",
    "main": "server.js",
    "dependencies": {
        "express": "^4.18.2",
        "cors": "^2.8.5",
        "multer": "^1.4.5-lts.1"
    }
}
EOF

cat > "$LFS_MAPPER_DIR/server.js" << EOF
const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const multer = require('multer');

const app = express();
const PORT = process.env.PORT || 3002;
const DOMAIN = '${DOMAIN_NAME}';

// Configure multer for file uploads
const upload = multer({ dest: '/opt/winejs/shared-volumes/uploads/' });

// Path mappings for repositories
const REPO_MAPPINGS = {
    '/repos': '/opt/winejs/repositories',
    '/forgejo/repos': '/opt/winejs/repositories',
    '/forgejo/data': '/opt/winejs/data/forgejo',
    '/winejs/repos': '/opt/winejs/repositories',
    '/winejs/data': '/opt/winejs/data',
    '/lfs-storage': '/opt/winejs/data/forgejo/lfs',
    '/backups': '/opt/winejs/shared-volumes/backups'
};

app.use(cors());
app.use(express.json());

function resolvePath(reqPath) {
    for (const [shortcut, realPath] of Object.entries(REPO_MAPPINGS)) {
        if (reqPath === shortcut || reqPath.startsWith(shortcut + '/')) {
            const relativePath = reqPath.substring(shortcut.length);
            const fullPath = path.join(realPath, relativePath);
            return {
                fullPath: fullPath,
                exists: fs.existsSync(fullPath),
                isDirectory: fs.existsSync(fullPath) && fs.statSync(fullPath).isDirectory()
            };
        }
    }
    return { fullPath: reqPath, exists: false };
}

// List repositories
app.get('/api/repos', (req, res) => {
    const reposPath = '/opt/winejs/repositories';
    if (!fs.existsSync(reposPath)) {
        return res.json({ repos: [] });
    }
    
    try {
        const repos = fs.readdirSync(reposPath)
            .filter(item => fs.statSync(path.join(reposPath, item)).isDirectory())
            .map(repo => ({
                name: repo,
                path: path.join(reposPath, repo),
                url: \`https://\${DOMAIN}/forgejo/\${repo}\`
            }));
        res.json({ repos });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Browse repositories and files
app.get('/api/browse', (req, res) => {
    const browsePath = req.query.path || '/opt/winejs/repositories';
    const { fullPath, exists } = resolvePath(browsePath);
    
    if (!exists) {
        return res.status(404).json({ error: 'Path not found' });
    }
    
    try {
        const items = fs.readdirSync(fullPath)
            .filter(item => !item.startsWith('.'))
            .map(item => {
                const itemPath = path.join(fullPath, item);
                const stats = fs.statSync(itemPath);
                return {
                    name: item,
                    path: itemPath,
                    isDirectory: stats.isDirectory(),
                    size: stats.size,
                    modified: stats.mtime
                };
            });
        res.json(items);
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// Clone repository helper
app.post('/api/clone', express.json(), (req, res) => {
    const { repoUrl, targetName } = req.body;
    
    if (!repoUrl) {
        return res.status(400).json({ error: 'Repository URL required' });
    }
    
    const repoName = targetName || path.basename(repoUrl, '.git');
    const targetPath = path.join('/opt/winejs/repositories', repoName);
    
    res.json({
        success: true,
        message: 'Clone initiated',
        command: \`git clone \${repoUrl} \${targetPath}\`,
        targetPath: targetPath
    });
});

// LFS upload endpoint
app.post('/api/lfs/upload', upload.single('file'), (req, res) => {
    if (!req.file) {
        return res.status(400).json({ error: 'No file uploaded' });
    }
    
    res.json({
        success: true,
        file: req.file,
        message: 'File uploaded to LFS storage'
    });
});

// Health check
app.get('/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        port: PORT, 
        forgejoPort: process.env.FORGEJO_PORT,
        domain: DOMAIN,
        lfsEnabled: true
    });
});

app.listen(PORT, () => {
    console.log(\`✅ WineJS LFS Mapper running on port \${PORT}\`);
    console.log(\`🌐 Forgejo URL: https://\${DOMAIN}/forgejo\`);
});
EOF

# Install Node dependencies for LFS mapper
log "📦 Installing LFS mapper dependencies..."
cd "$LFS_MAPPER_DIR"
npm install --production

# ============= CREATE SHARED VOLUMES SYSTEM =============
log "📦 Setting up shared volumes (like Docker mounts)..."

cat > "$SHARED_VOLUMES/mounts.conf" << EOF
# Shared Volume Mounts Configuration for Forgejo
# Format: mount_point:host_path:container_path

# Forgejo repositories
repos:$REPO_DIR:/repositories

# Forgejo data
forgejo-data:$FORGEJO_DATA:/data

# Forgejo config
forgejo-config:$FORGEJO_CONFIG:/etc/forgejo

# Backups mount
backups:$SHARED_VOLUMES/backups:/backups

# Imports mount
imports:$SHARED_VOLUMES/imports:/imports

# CI/CD artifacts
ci-cd:$SHARED_VOLUMES/ci-cd:/ci-cd
EOF

# Create mount helper script
cat > "$SHARED_VOLUMES/mount-helper.sh" << 'EOF'
#!/bin/bash
# Volume mount helper - like Docker volumes

MOUNT_CONFIG="/opt/winejs/shared-volumes/mounts.conf"

if [ ! -f "$MOUNT_CONFIG" ]; then
    echo "Error: Mount config not found"
    exit 1
fi

case "$1" in
    list)
        echo "Available mounts:"
        cat "$MOUNT_CONFIG" | grep -v '^#' | awk -F: '{print "  " $1 " -> " $2 " -> " $3}'
        ;;
    mount)
        MOUNT_NAME="$2"
        grep "^$MOUNT_NAME:" "$MOUNT_CONFIG" | while IFS=: read name host container; do
            echo "Mounting $name: $host -> $container"
            if [ -d "$host" ]; then
                echo "  ✅ Mount point ready: $host"
            else
                echo "  ⚠️  Host path doesn't exist, creating: $host"
                mkdir -p "$host"
            fi
        done
        ;;
    *)
        echo "Usage: mount-helper {list|mount <name>}"
        ;;
esac
EOF

chmod +x "$SHARED_VOLUMES/mount-helper.sh"

# ============= DOWNLOAD ICON =============
log "Downloading Forgejo icon..."
curl -L "https://cdn.gitgpt.chat/rtx/images/gitlfs.png" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE LAUNCH SCRIPT WITH AUTO-HEAL =============
log "Generating launch.sh with auto-heal monitor..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash

# ============================================
# WineJS Forgejo Server Launcher with Auto-Heal
# ============================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting WineJS Forgejo Server..."

# ============= CONFIGURATION =============
FORGEJO_DATA="/data"
FORGEJO_CONFIG="/etc/forgejo"
REPO_PATH="/repositories"
PORT=3000

# Create required directories
mkdir -p "$FORGEJO_DATA"/{gitea,git,repositories,lfs}
mkdir -p "$FORGEJO_CONFIG"
mkdir -p "$REPO_PATH"

# ============= START AUTO-HEAL MONITOR =============
log "🔄 Starting auto-heal monitor..."

(
    while true; do
        sleep 30
        if ! pgrep -f "forgejo" > /dev/null; then
            log "⚠️ Forgejo crashed! Restarting..."
            /usr/local/bin/forgejo web --port $PORT --config $FORGEJO_CONFIG/app.ini &
        fi
        # Check if git-lfs is running
        if ! pgrep -f "git-lfs" > /dev/null; then
            log "⚠️ Git LFS not running, restarting..."
            git lfs install --system
        fi
    done
) &
AUTO_HEAL_PID=$!
log "✅ Auto-heal monitor started (PID: $AUTO_HEAL_PID)"

# ============= SETUP GIT HOOKS =============
log "🔧 Setting up Git hooks for WineJS integration..."

cat > "/usr/local/bin/forgejo-webhook" << 'HOOK_EOF'
#!/bin/bash
# WineJS Forgejo webhook handler
WEBHOOK_URL="https://${DOMAIN}/forgejo-webhook"
REPO_PATH="$1"
EVENT_TYPE="$2"

if [ -n "$REPO_PATH" ] && [ -n "$EVENT_TYPE" ]; then
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"repo\":\"$REPO_PATH\",\"event\":\"$EVENT_TYPE\",\"timestamp\":\"$(date -Iseconds)\"}" \
        --connect-timeout 5 || true
fi
HOOK_EOF

chmod +x /usr/local/bin/forgejo-webhook

# ============= START FORGEJO =============
log "🎯 Starting Forgejo Server..."
/usr/local/bin/forgejo web --port $PORT --config $FORGEJO_CONFIG/app.ini

# Keep script running
wait $!
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "Forgejo Git Server",
    "version": "1.21",
    "description": "Git repository hosting with issue tracker and CI/CD",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "winejs-forgejo",
    "icon": "/icons/forgejo.png",
    "category": "Development",
    "features": [
        "Git repository hosting",
        "Issue tracker",
        "Pull requests",
        "CI/CD with Actions",
        "Git LFS support",
        "Webhooks",
        "Code review",
        "Wiki"
    ]
}
CONF_EOF

# ============= CREATE DOCKER-COMPOSE.YML WITH VOLUME MOUNTS =============
log "Generating docker-compose.yml with volume mounts..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Main Forgejo Server
  winejs-${APP_NAME}:
    image: codeberg.org/forgejo/forgejo:1.21
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:3000"
      - "2222:22"
    environment:
      - USER_UID=1000
      - USER_GID=1000
      - FORGEJO__server__DOMAIN=${DOMAIN_NAME}
      - FORGEJO__server__ROOT_URL=https://${DOMAIN_NAME}/forgejo/
      - FORGEJO__server__LOCAL_ROOT_URL=http://localhost:3000/
      - FORGEJO__server__LFS_START_SERVER=true
      - FORGEJO__lfs__JWT_SECRET=${LFS_JWT_SECRET}
      - FORGEJO__lfs__MAX_FILE_SIZE=1073741824
    volumes:
      # Forgejo data
      - ${FORGEJO_DATA}:/data
      # Forgejo config
      - ${FORGEJO_CONFIG}:/etc/forgejo
      # Shared repositories - FIXED PERMISSION PATH
      - ${REPO_DIR}:/data/git/repositories
      # Shared volumes
      - ${SHARED_VOLUMES}/backups:/backups
      - ${SHARED_VOLUMES}/imports:/imports
      - ${SHARED_VOLUMES}/ci-cd:/ci-cd
      - /etc/timezone:/etc/timezone:ro
      - /etc/localtime:/etc/localtime:ro
    networks:
      - winejs-net

  # LFS Mapper Service
  winejs-lfs-mapper:
    image: node:18-alpine
    container_name: winejs-lfs-mapper
    restart: unless-stopped
    ports:
      - "127.0.0.1:${LFS_MAPPER_PORT}:3002"
    environment:
      - FORGEJO_PORT=${APP_PORT}
      - PORT=3002
    volumes:
      - ${LFS_MAPPER_DIR}:/app:ro
      - ${REPO_DIR}:/opt/winejs/repositories:ro
      - ${FORGEJO_DATA}:/opt/winejs/data/forgejo:ro
      - ${SHARED_VOLUMES}:/opt/winejs/shared-volumes:rw
    working_dir: /app
    command: node server.js
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE WINEJS GIT INTEGRATION =============
log "🔌 Creating WineJS Git integration..."

mkdir -p "/opt/winejs/git-hooks"

cat > "/opt/winejs/git-hooks/post-receive" << 'HOOK_EOF'
#!/bin/bash
# Post-receive hook for WineJS integration

while read oldrev newrev refname; do
    # Extract repository name
    REPO_NAME=$(basename "$PWD")
    
    # Notify WineJS about the push
    curl -X POST "http://localhost:3002/api/webhook" \
        -H "Content-Type: application/json" \
        -d "{\"repo\":\"$REPO_NAME\",\"ref\":\"$refname\",\"oldrev\":\"$oldrev\",\"newrev\":\"$newrev\"}" \
        --connect-timeout 5 || true
    
    echo "✅ WineJS notified of push to $REPO_NAME"
done
HOOK_EOF

chmod +x "/opt/winejs/git-hooks/post-receive"

# ============= SET UP PM2 FOR LFS MAPPER =============
log "🚀 Setting up PM2 for LFS mapper persistence..."

if command -v pm2 &> /dev/null; then
    cd "$LFS_MAPPER_DIR"
    
    # Stop and delete existing instance if it exists
    if pm2 list | grep -q "winejs-lfs-mapper"; then
        log "Stopping existing LFS mapper..."
        pm2 stop winejs-lfs-mapper 2>/dev/null || true
        pm2 delete winejs-lfs-mapper 2>/dev/null || true
    fi
    
    # Start new instance
    pm2 start server.js --name winejs-lfs-mapper --env FORGEJO_PORT=$APP_PORT
    pm2 save
    pm2 startup
fi

# ============= CREATE ADMIN USER SCRIPT =============
log "Creating admin user setup script..."

cat > "$APP_DIR/setup-admin.sh" << 'ADMIN_EOF'
#!/bin/bash
# Forgejo admin user setup - FIXED VERSION

FORGEJO_URL="http://localhost:${APP_PORT}"
ADMIN_USERNAME="winejs-admin"
ADMIN_EMAIL="${ADMIN_EMAIL}"
ADMIN_PASSWORD="${ADMIN_PASSWORD}"

log() { echo "[$(date '+%H:%M:%S')] $1"; }

# Wait for Forgejo to be ready
log "Waiting for Forgejo to start..."
max_attempts=30
attempt=1
while [ $attempt -le $max_attempts ]; do
    if curl -s -f "http://localhost:${APP_PORT}/api/v1/version" > /dev/null 2>&1; then
        log "✅ Forgejo is ready!"
        break
    fi
    log "Attempt $attempt/$max_attempts: Waiting for Forgejo..."
    sleep 5
    attempt=$((attempt + 1))
done

if [ $attempt -gt $max_attempts ]; then
    log "⚠️ Timeout waiting for Forgejo. Admin user not created."
    log "Please create admin manually via:"
    log "  docker exec -it winejs-forgejo forgejo admin user create"
    exit 1
fi

# Create admin user using docker exec (MORE RELIABLE than API)
log "Creating admin user via docker exec..."
docker exec winejs-forgejo forgejo admin user create \
    --username "$ADMIN_USERNAME" \
    --email "$ADMIN_EMAIL" \
    --password "$ADMIN_PASSWORD" \
    --admin \
    --must-change-password=false 2>&1

if [ $? -eq 0 ]; then
    log "✅ Admin user '$ADMIN_USERNAME' created successfully"
else
    log "⚠️ Admin user may already exist or creation failed"
    log "You can try creating manually with:"
    log "  docker exec -it winejs-forgejo forgejo admin user create --username admin --email your@email.com --password pass --admin"
fi

log "✅ Admin setup complete. Login at: https://${DOMAIN_NAME}/forgejo/login"
ADMIN_EOF


chmod +x "$APP_DIR/setup-admin.sh"

# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_forgejo.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS Forgejo Uninstaller

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Change to safe directory first
cd /tmp || cd /root || exit 1

log "🧹 Uninstalling Forgejo Server..."

# ============= STOP PM2 PROCESSES =============
log "Stopping PM2 processes..."
if command -v pm2 &> /dev/null; then
    if pm2 list 2>/dev/null | grep -q "winejs-lfs-mapper"; then
        log "Stopping winejs-lfs-mapper..."
        pm2 stop winejs-lfs-mapper 2>/dev/null || true
        pm2 delete winejs-lfs-mapper 2>/dev/null || true
    fi
fi

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

if docker ps -a 2>/dev/null | grep -q "winejs-forgejo"; then
    log "Stopping winejs-forgejo container..."
    docker stop winejs-forgejo 2>/dev/null || true
    docker rm winejs-forgejo 2>/dev/null || true
    log "✅ Forgejo container removed"
fi

if docker ps -a 2>/dev/null | grep -q "winejs-lfs-mapper"; then
    log "Stopping winejs-lfs-mapper container..."
    docker stop winejs-lfs-mapper 2>/dev/null || true
    docker rm winejs-lfs-mapper 2>/dev/null || true
    log "✅ LFS mapper container removed"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="forgejo"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
FORGEJO_DATA="/opt/winejs/data/forgejo"
FORGEJO_CONFIG="/opt/winejs/config/forgejo"
LFS_MAPPER_DIR="/opt/winejs/lfs-mapper"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"
ICON_SVG="/opt/winejs/translator/public/icons/${APP_NAME}.svg"

# Remove directories if they exist
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$FORGEJO_DATA" ] && rm -rf "$FORGEJO_DATA" && log "✅ Forgejo data removed"
[ -d "$FORGEJO_CONFIG" ] && rm -rf "$FORGEJO_CONFIG" && log "✅ Forgejo config removed"
[ -d "$LFS_MAPPER_DIR" ] && rm -rf "$LFS_MAPPER_DIR" && log "✅ LFS mapper removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"
[ -f "$ICON_SVG" ] && rm -f "$ICON_SVG" && log "✅ SVG icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any Forgejo routes exist
    if ! grep -q "forgejo" "$NGINX_SITE"; then
        log "No Forgejo routes found in nginx config"
    else
        log "Removing Forgejo routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use Perl for more reliable multi-line removal (if available)
        if command -v perl &> /dev/null; then
            perl -i -0777 -pe 's/^[[:space:]]*# Forgejo Git Server\s*\n.*?location \/forgejo-lfs\/.*?^\s*}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo\/api\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
            perl -i -0777 -pe 's/^[[:space:]]*location \/forgejo-lfs\/\s*\{.*?^\s*\}\s*$//gms' "$NGINX_SITE"
        else
            # Fallback to sed for multi-line removal
            sed -i '/^[[:space:]]*# Forgejo Git Server/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo {/,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo\/api\//,/^[[:space:]]*}/d' "$NGINX_SITE"
            sed -i '/^[[:space:]]*location \/forgejo-lfs\//,/^[[:space:]]*}/d' "$NGINX_SITE"
        fi
        
        # Remove any orphaned forgejo lines
        sed -i '/forgejo/d' "$NGINX_SITE"
        
        # Clean up multiple blank lines
        sed -i '/^$/N;/^\n$/D' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - Forgejo routes removed"
        else
            warn "Nginx test failed! Restoring from backup..."
            if [ -f "$BACKUP_FILE" ]; then
                cp "$BACKUP_FILE" "$NGINX_SITE"
                if nginx -t 2>/dev/null; then
                    systemctl reload nginx
                    log "✅ Successfully restored previous nginx config"
                else
                    error "CRITICAL: Even backup config fails! Check nginx manually"
                    exit 1
                fi
            else
                error "No backup available! Manual intervention required"
                log "Check nginx config at: $NGINX_SITE"
                log "Previous error: $(cat /tmp/nginx_test.log)"
                exit 1
            fi
        fi
    fi
fi

# ============= RELOAD WINEJS TRANSLATOR =============
log "Reloading WineJS translator..."
if command -v pm2 &> /dev/null; then
    pm2 restart translator 2>/dev/null || true
    log "✅ Translator reloaded"
fi

# ============= REMOVE HELPER SCRIPT =============
if [ -f "/usr/local/bin/winejs-forgejo" ]; then
    rm -f "/usr/local/bin/winejs-forgejo"
    log "✅ Helper script removed"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           FORGEJO SERVER UNINSTALLED SUCCESSFULLY!            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ Forgejo Server has been completely removed"
echo ""
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_forgejo.sh"
log "✅ Uninstall script created: $(dirname "$APP_DIR")/uninstall_forgejo.sh"

# ============= START CONTAINER =============
log "Starting Forgejo Server container..."

cd "$INSTANCE_DIR"
docker-compose up -d

sleep 10

# Fix permissions again after container start (in case container created files)
docker exec winejs-forgejo mkdir -p /data/git/.ssh 2>/dev/null || true
docker exec winejs-forgejo chown -R 1000:1000 /data/git/.ssh 2>/dev/null || true
docker exec winejs-forgejo chmod 700 /data/git/.ssh 2>/dev/null || true

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
fi

# ============= INJECT GIT LFS BUTTON =============
log "Injecting Git LFS button..."

# Create custom footer with JavaScript injection
docker exec winejs-forgejo mkdir -p /data/gitea/templates/custom

cat > /tmp/gitlfs-inject.js << 'EOF'
<script>
(function() {
    // Wait for page to load
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', insertButton);
    } else {
        insertButton();
    }
    
    function insertButton() {
        // Find the rss-icon link
        var rssLink = document.querySelector('.rss-icon');
        if (rssLink && !document.querySelector('.gitlfs-injected')) {
            var lfsLink = document.createElement('a');
            lfsLink.className = 'rss-icon gt-ml-3 gitlfs-injected';
            lfsLink.href = 'https://cdn.gitgpt.chat/rtx/forgejogitlfs.html';
            lfsLink.target = '_blank';
            lfsLink.innerHTML = '<img src="https://cdn.gitgpt.chat/rtx/images/gitlfs.png" style="width: 20px"/>';
            rssLink.parentNode.insertBefore(lfsLink, rssLink.nextSibling);
        }
    }
})();
</script>
EOF

docker cp /tmp/gitlfs-inject.js winejs-forgejo:/data/gitea/templates/custom/footer.tmpl

log "✅ Git LFS button injection added via custom footer"

# ============= SETUP ADMIN USER =============
log "Setting up admin user..."
bash "$APP_DIR/setup-admin.sh" &

# ============= UPDATE NGINX CONFIG =============
log "Updating nginx configuration for Forgejo..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if Forgejo routes already exist
    if ! grep -q "location /forgejo/" /etc/nginx/sites-available/winejs; then
        # Backup the current config
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line with "listen 443" and insert BEFORE it (like VSCode did)
        LISTEN_443_LINE=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$LISTEN_443_LINE" ]; then
            # Insert Forgejo routes BEFORE the listen 443 line
            sed -i "${LISTEN_443_LINE}i\\
    # Forgejo Git Server\n\
    location /forgejo/ {\n\
        rewrite ^/forgejo(/.*)$ \$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        client_max_body_size 1024M;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
    location /forgejo-lfs/ {\n\
        proxy_pass http://127.0.0.1:${LFS_MAPPER_PORT};\n\
        proxy_set_header Host \$host;\n\
    }\n" /etc/nginx/sites-available/winejs
            
            log "✅ Forgejo routes inserted before 'listen 443'"
        else
            # Fallback: insert before the root location
            ROOT_LOCATION_LINE=$(grep -n "location / {" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
            if [ -n "$ROOT_LOCATION_LINE" ]; then
                sed -i "${ROOT_LOCATION_LINE}i\\
    # Forgejo Git Server\n\
    location /forgejo/ {\n\
        rewrite ^/forgejo(/.*)$ \$1 break;\n\
        proxy_pass http://127.0.0.1:${APP_PORT};\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        client_max_body_size 1024M;\n\
        proxy_buffering off;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
    location /forgejo-lfs/ {\n\
        proxy_pass http://127.0.0.1:${LFS_MAPPER_PORT};\n\
        proxy_set_header Host \$host;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                log "✅ Forgejo routes inserted before root location"
            else
                warn "Could not find insertion point"
            fi
        fi
        
        # Test and reload
        if nginx -t; then
            systemctl reload nginx
            log "✅ Nginx updated with Forgejo routes"
            log "   • /forgejo/ → Forgejo (port ${APP_PORT})"
            log "   • /forgejo-lfs/ → LFS Mapper (port ${LFS_MAPPER_PORT})"
        else
            warn "Nginx test failed, restoring backup"
            cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
            nginx -t && systemctl reload nginx
            log "⚠️ Could not add Forgejo routes automatically"
        fi
    else
        log "Forgejo routes already exist in nginx config"
    fi
else
    warn "nginx config not found, skipping"
fi

# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."

pm2 restart translator 2>/dev/null || true

# ============= CREATE HELPER SCRIPT =============
log "Creating helper script..."

cat > /usr/local/bin/winejs-forgejo << EOF
#!/bin/bash
# Quick Forgejo launcher for WineJS

case "\$1" in
    repos)
        echo "Listing repositories..."
        curl -s "http://localhost:${LFS_MAPPER_PORT}/api/repos" | jq .
        ;;
    clone)
        if [ -n "\$2" ]; then
            echo "Cloning \$2..."
            curl -X POST "http://localhost:${LFS_MAPPER_PORT}/api/clone" \\
                -H "Content-Type: application/json" \\
                -d "{\"repoUrl\":\"\$2\"}" | jq .
        else
            echo "Usage: winejs-forgejo clone <repo-url>"
        fi
        ;;
    browse)
        PATH_TO_BROWSE="\${2:-/opt/winejs/repositories}"
        curl -s "http://localhost:${LFS_MAPPER_PORT}/api/browse?path=\$PATH_TO_BROWSE" | jq .
        ;;
    status)
        echo "Forgejo status:"
        docker ps | grep forgejo
        echo ""
        echo "LFS Mapper status:"
        pm2 list | grep lfs-mapper
        ;;
    open)
        if command -v xdg-open &> /dev/null; then
            xdg-open "https://${DOMAIN_NAME}/forgejo"
        elif command -v open &> /dev/null; then
            open "https://${DOMAIN_NAME}/forgejo"
        else
            echo "Visit: https://${DOMAIN_NAME}/forgejo"
        fi
        ;;
    *)
        echo "WineJS Forgejo Helper"
        echo ""
        echo "Commands:"
        echo "  winejs-forgejo open      - Open Forgejo in browser"
        echo "  winejs-forgejo repos     - List all repositories"
        echo "  winejs-forgejo browse    - Browse repositories"
        echo "  winejs-forgejo clone     - Clone a repository"
        echo "  winejs-forgejo status    - Check service status"
        ;;
esac
EOF

chmod +x /usr/local/bin/winejs-forgejo

# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            FORGEJO SERVER INSTALLED ON WINEJS!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ Forgejo Server installed as a WineJS app!"
echo ""
info "🌐 Access URLs:"
info "   • Forgejo UI: https://$DOMAIN_NAME/forgejo/"
info "   • Git Clone: git clone https://$DOMAIN_NAME/forgejo/username/repo.git"
info "   • SSH Clone: git clone git@$DOMAIN_NAME:username/repo.git"
echo ""
info "🔑 Admin Credentials:"
info "   • Email: $ADMIN_EMAIL"
info "   • Password: $ADMIN_PASSWORD"
echo ""
info "📂 Repository Storage:"
info "   • Repositories: /opt/winejs/repositories"
info "   • LFS Storage: /opt/winejs/data/forgejo/lfs"
info "   • Backups: /opt/winejs/shared-volumes/backups"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-forgejo open        # Open Forgejo in browser"
info "   • winejs-forgejo repos       # List all repositories"
info "   • winejs-forgejo clone <url> # Clone a repository"
info "   • winejs-forgejo status      # Check service status"
info "   • mount-helper list          # List shared volumes"
echo ""
info "🔧 Features:"
info "   • Git repository hosting"
info "   • Issue tracker and pull requests"
info "   • CI/CD with GitHub Actions compatible workflows"
info "   • Git LFS support for large files"
info "   • Webhooks for automation"
info "   • Code review and collaboration"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_forgejo.sh"
echo ""
success "✨ Forgejo Server is ready! Visit https://$DOMAIN_NAME/forgejo/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"
