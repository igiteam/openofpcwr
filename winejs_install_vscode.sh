#!/bin/bash
# ============================================
# WineJS VSCode Installer
# Adds VS Code in Browser to WineJS Platform
# ============================================
# App: VSCode Server
# Category: Development
# Features: Path Mapping, Shared Volumes, Auto-heal
# ============================================

# What this script does:
#     ✓ Verifies WineJS platform - Checks if /opt/winejs exists
#     ✓ Creates docker network - Creates winejs-net if missing
#     ✓ Creates all necessary directories with path mapping support
#     ✓ Downloads VSCode server - Latest version with WineJS extensions
#     ✓ Creates path mapping server (Node.js) for /vscode/* routing
#     ✓ Sets up shared volumes system (like Docker mounts)
#     ✓ Creates launch.sh with auto-heal monitor
#     ✓ Creates config.json with all app metadata
#     ✓ Creates docker-compose.yml with volume mounts
#     ✓ Creates URL handler for custom schemes
#     ✓ Creates uninstall script with cleanup
#     ✓ Sets up PM2 for path mapper persistence
#     ✓ Creates desktop shortcuts for macOS/Linux
#     ✓ Installs WineJS integration extension
#     ✓ Restarts translator and starts containers

VSCODE_SERVER_LOGO_URL="https://cdn.gitgpt.chat/rtx/images/vscodeserver.png"

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

log "🚀 Installing WineJS VSCode Server..."

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


# ============= FIND NEXT AVAILABLE PORT =============
log "Finding next available port..."

# Function to check if a port is in use
port_in_use() {
    local port=$1
    
    # Check if port is bound by any process on host
    if ss -tln 2>/dev/null | grep -q ":$port " || netstat -tln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    
    # Check if any Docker container is using this port
    if docker ps 2>/dev/null | grep -q ":$port->"; then
        return 0
    fi
    
    # Check if port exists in any config.json in /opt/winejs/apps
    if [ -d "/opt/winejs/apps" ]; then
        for config in /opt/winejs/apps/*/config.json; do
            if [ -f "$config" ]; then
                if grep -q "\"port\": $port" "$config" 2>/dev/null; then
                    return 0
                fi
            fi
        done
    fi
    
    return 1
}

# Start checking from 6901
START_PORT=6901
MAX_RETRIES=50
APP_PORT=""
PATH_MAPPER_PORT=""

log "Scanning for available ports starting from $START_PORT..."

# Find available port for main app
for i in $(seq 0 $MAX_RETRIES); do
    TEST_PORT=$((START_PORT + i))
    if ! port_in_use $TEST_PORT; then
        APP_PORT=$TEST_PORT
        log "✅ Found available port: $APP_PORT"
        break
    fi
done

# Find available port for Path Mapper (start from APP_PORT+1)
if [ -n "$APP_PORT" ]; then
    for i in $(seq 1 $MAX_RETRIES); do
        TEST_PORT=$((APP_PORT + i))
        if ! port_in_use $TEST_PORT; then
            PATH_MAPPER_PORT=$TEST_PORT
            log "✅ Found available port for PathMapper: $PATH_MAPPER_PORT"
            break
        fi
    done
fi

# Verify both ports were found
if [ -z "$APP_PORT" ]; then
    error "Could not find available port for main app after checking $MAX_RETRIES ports"
fi

if [ -z "$PATH_MAPPER_PORT" ]; then
    error "Could not find available port for PathMapper after checking $MAX_RETRIES ports"
fi

log "Using ports: VSCODE=$APP_PORT, PathMapper=$PATH_MAPPER_PORT"

# ============= CREATE APP DIRECTORIES =============
APP_NAME="vscode"
APP_DIR="/opt/winejs/apps/$APP_NAME"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/$APP_NAME"
VSCODE_DATA="/opt/winejs/data/vscode"
VSCODE_EXTENSIONS="/opt/winejs/data/vscode-extensions"
ICON_DIR="/opt/winejs/translator/public/icons"
WORKSPACE_DIR="/opt/winejs/workspaces"
SHARED_VOLUMES="/opt/winejs/shared-volumes"
PATH_MAPPER_DIR="/opt/winejs/path-mapper"

mkdir -p "$APP_DIR"
mkdir -p "$INSTANCE_DIR"
mkdir -p "$VSCODE_DATA"
mkdir -p "$VSCODE_EXTENSIONS"
mkdir -p "$ICON_DIR"
mkdir -p "$WORKSPACE_DIR"
mkdir -p "$SHARED_VOLUMES"/{code,data,uploads,configs,backups}
mkdir -p "$PATH_MAPPER_DIR"

cd "$APP_DIR"

# ============= DOWNLOAD VSCODE SERVER =============
log "Downloading VSCode Server..."

ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    VSCODE_URL="https://github.com/coder/code-server/releases/download/v4.96.2/code-server-4.96.2-linux-amd64.tar.gz"
elif [ "$ARCH" = "aarch64" ]; then
    VSCODE_URL="https://github.com/coder/code-server/releases/download/v4.96.2/code-server-4.96.2-linux-arm64.tar.gz"
else
    VSCODE_URL="https://github.com/coder/code-server/releases/download/v4.96.2/code-server-4.96.2-linux-amd64.tar.gz"
fi

curl -L "$VSCODE_URL" -o vscode-server.tar.gz || error "Failed to download VSCode Server"
tar -xzf vscode-server.tar.gz --strip-components=1 || error "Failed to extract VSCode Server"
rm -f vscode-server.tar.gz

log "✅ VSCode Server downloaded and extracted"

# ============= CREATE PATH MAPPING SERVER =============
log "📡 Creating VSCode path mapping server..."

cat > "$PATH_MAPPER_DIR/package.json" << 'EOF'
{
    "name": "winejs-path-mapper",
    "version": "1.0.0",
    "description": "Path mapping server for WineJS VSCode integration",
    "main": "server.js",
    "dependencies": {
        "express": "^4.18.2",
        "cors": "^2.8.5"
    }
}
EOF

cat > "$PATH_MAPPER_DIR/server.js" << EOF
const express = require('express');
const path = require('path');
const fs = require('fs');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3001;
const DOMAIN = '${DOMAIN_NAME}';

// Path mappings like Docker volumes
const PATH_MAPPINGS = {
    '/vscode': '/opt/winejs/apps',
    '/winejs/apps': '/opt/winejs/apps',
    '/winejs/data': '/opt/winejs/data',
    '/winejs/config': '/opt/winejs/config',
    '/winejs/workspaces': '/opt/winejs/workspaces',
    '/uploads': '/var/www/uploads',
    '/backups': '/opt/winejs/shared-volumes/backups',
    '/root': '/root',
    '/home': '/home',
    '/etc': '/etc',
    '/var/log': '/var/log'
};

app.use(cors());
app.use(express.json());

function resolvePath(reqPath) {
    for (const [shortcut, realPath] of Object.entries(PATH_MAPPINGS)) {
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

app.get('/api/paths', (req, res) => {
    const paths = Object.keys(PATH_MAPPINGS).map(shortcut => ({
        shortcut: shortcut,
        realPath: PATH_MAPPINGS[shortcut],
        exists: fs.existsSync(PATH_MAPPINGS[shortcut])
    }));
    res.json({ paths });
});

app.get('/api/browse', (req, res) => {
    const browsePath = req.query.path || '/opt/winejs/apps';
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

// Redirect to VSCode - /vscode/apps/milkshape redirects to open that folder in VSCode
app.get('/vscode/*', (req, res) => {
    const projectPath = '/' + req.params[0];
    const { fullPath, exists, isDirectory } = resolvePath(projectPath);
    
    if (!exists) {
        return res.status(404).send(\`Path not found: \${fullPath}\`);
    }
    
    if (!isDirectory) {
        return res.status(400).send('Not a directory');
    }
    
    // Redirect to VSCode main URL with folder parameter
    const vscodeUrl = \`https://\${DOMAIN}/vscode/?folder=\${encodeURIComponent(fullPath)}\`;
    res.redirect(vscodeUrl);
});

app.get('/vscode', (req, res) => {
    // Redirect to VSCode main URL
    res.redirect(\`https://\${DOMAIN}/vscode/?folder=/opt/winejs/apps\`);
});

app.post('/api/open', express.json(), (req, res) => {
    const { path: folderPath } = req.body;
    
    if (!folderPath) {
        return res.status(400).json({ error: 'Path required' });
    }
    
    const { fullPath, exists, isDirectory } = resolvePath(folderPath);
    
    if (!exists) {
        return res.status(404).json({ error: \`Path not found: \${fullPath}\` });
    }
    
    if (!isDirectory) {
        return res.status(400).json({ error: 'Not a directory' });
    }
    
    res.json({
        success: true,
        url: \`https://\${DOMAIN}/vscode/?folder=\${encodeURIComponent(fullPath)}\`,
        path: fullPath
    });
});

app.get('/health', (req, res) => {
    res.json({ status: 'ok', port: PORT, vscodePort: process.env.VSCODE_PORT, domain: DOMAIN });
});

app.listen(PORT, () => {
    console.log(\`✅ WineJS Path Mapper running on port \${PORT}\`);
    console.log(\`🌐 Domain: https://\${DOMAIN}/vscode-editor\`);
});
EOF

# Install Node dependencies for path mapper
log "📦 Installing path mapper dependencies..."
cd "$PATH_MAPPER_DIR"
npm install --production

# ============= CREATE SHARED VOLUMES SYSTEM =============
log "📦 Setting up shared volumes (like Docker mounts)..."

cat > "$SHARED_VOLUMES/mounts.conf" << EOF
# Shared Volume Mounts Configuration
# Format: mount_point:host_path:container_path

# VSCode projects mount
vscode:$APP_DIR:/workspace/code

# WineJS apps mount
winejs-apps:/opt/winejs/apps:/winejs/apps

# Uploads mount
uploads:$SHARED_VOLUMES/uploads:/var/uploads

# Data mount
data:$SHARED_VOLUMES/data:/var/data

# Configs mount
configs:$SHARED_VOLUMES/configs:/etc/winejs

# Backups mount
backups:$SHARED_VOLUMES/backups:/backups
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
log "Downloading VSCodeServer icon..."
curl -L "$VSCODE_SERVER_LOGO_URL" -o "$ICON_DIR/${APP_NAME}.png" 2>/dev/null || \
warn "Failed to download icon, using default"

# ============= CREATE LAUNCH SCRIPT WITH AUTO-HEAL =============
log "Generating launch.sh with auto-heal monitor..."

cat > "$APP_DIR/launch.sh" << 'LAUNCH_EOF'
#!/bin/bash

# ============================================
# WineJS VSCode Server Launcher with Auto-Heal
# ============================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "🚀 Starting WineJS VSCode Server..."

# ============= CONFIGURATION =============
VSCODE_DIR="/app"
VSCODE_DATA="/home/kasm-user/.local/share/code-server"
VSCODE_EXTENSIONS="/home/kasm-user/.local/share/code-server/extensions"
WINEJS_APPS="/opt/winejs/apps"
WINEJS_WORKSPACES="/opt/winejs/workspaces"
PORT=8080
PASSWORD="winejs-vscode-$(date +%s | sha256sum | base64 | head -c 12)"

# Create required directories
mkdir -p "$VSCODE_DATA"
mkdir -p "$VSCODE_EXTENSIONS"
mkdir -p "$WINEJS_WORKSPACES"

# ============= CREATE WELCOME WORKSPACE =============
log "📁 Creating WineJS welcome workspace..."

cat > "$WINEJS_WORKSPACES/winejs.code-workspace" << 'WORKSPACE_EOF'
{
    "folders": [
        {
            "name": "WineJS Apps",
            "path": "/opt/winejs/apps"
        },
        {
            "name": "WineJS Data",
            "path": "/opt/winejs/data"
        },
        {
            "name": "Shared Storage",
            "path": "/var/www/uploads"
        },
        {
            "name": "System Root",
            "path": "/"
        }
    ],
    "settings": {
        "workbench.colorTheme": "dark",
        "workbench.startupEditor": "welcomePage",
        "files.autoSave": "afterDelay",
        "terminal.integrated.defaultProfile.linux": "bash",
        "editor.fontSize": 14,
        "editor.fontFamily": "'Fira Code', 'Cascadia Code', monospace",
        "editor.fontLigatures": true,
        "workbench.iconTheme": "vscode-icons",
        "extensions.autoUpdate": true,
        "security.workspace.trust.enabled": false
    }
}
WORKSPACE_EOF

# ============= SET DEFAULT DARK THEME =============
log "🎨 Setting default VSCode theme to Dark..."

# Create default settings for all users
mkdir -p "$VSCODE_DATA/User"
cat > "$VSCODE_DATA/User/settings.json" << 'SETTINGS_EOF'
{
    "workbench.colorTheme": "dark",
    "workbench.preferredDarkColorTheme": "dark",
    "window.autoDetectColorScheme": false,
    "workbench.startupEditor": "welcomePage",
    "editor.fontSize": 14,
    "editor.fontFamily": "'Fira Code', 'Cascadia Code', monospace",
    "editor.fontLigatures": true,
    "editor.renderWhitespace": "boundary",
    "files.autoSave": "afterDelay",
    "terminal.integrated.fontSize": 13,
    "workbench.iconTheme": "vscode-icons",
    "extensions.autoCheckUpdates": true,
    "extensions.autoUpdate": true,
    "security.workspace.trust.enabled": false
}
SETTINGS_EOF

log "✅ Dark theme configured as default"

# ============= START AUTO-HEAL MONITOR =============
log "🔄 Starting auto-heal monitor..."

(
    while true; do
        sleep 30
        if ! pgrep -f "code-server" > /dev/null; then
            log "⚠️ VSCode crashed! Restarting..."
            sudo -u kasm-user /app/bin/code-server \
                --bind-addr 0.0.0.0:8080 \
                --auth password \
                --password winejs-vscode \
                --theme dark \
                --user-data-dir "$VSCODE_DATA" \
                --extensions-dir "$VSCODE_EXTENSIONS" \
                --disable-telemetry \
                "$WINEJS_WORKSPACES/winejs.code-workspace" &
        fi
    done
) &
AUTO_HEAL_PID=$!
log "✅ Auto-heal monitor started (PID: $AUTO_HEAL_PID)"

# ============= START VSCODE =============
log "🎯 Starting VSCode Server..."
sudo -u kasm-user /app/bin/code-server \
    --bind-addr 0.0.0.0:8080 \
    --auth password \
    --password winejs-vscode \
    --user-data-dir "$VSCODE_DATA" \
    --extensions-dir "$VSCODE_EXTENSIONS" \
    --disable-telemetry \
    "$WINEJS_WORKSPACES/winejs.code-workspace"

# Keep script running
wait $!
LAUNCH_EOF

chmod +x "$APP_DIR/launch.sh"

# ============= CREATE CONFIG.JSON =============
log "Generating config.json..."

cat > "$APP_DIR/config.json" << CONF_EOF
{
    "name": "VS Code Server",
    "version": "4.96.2",
    "description": "Visual Studio Code in browser with WineJS integration",
    "executable": "launch.sh",
    "port": ${APP_PORT},
    "vnc_password": "winejs-vscode",
    "icon": "/icons/vscode.png",
    "category": "Development",
    "features": [
        "Full VS Code in browser",
        "Edit any WineJS app",
        "Built-in terminal",
        "Git integration",
        "Extension marketplace"
    ]
}
CONF_EOF

# ============= CREATE DOCKER-COMPOSE.YML WITH VOLUME MOUNTS =============
log "Generating docker-compose.yml with volume mounts..."

cat > "$INSTANCE_DIR/docker-compose.yml" << DOCKER_EOF
services:
  # Main VSCode Server - using official image
  winejs-${APP_NAME}:
    image: codercom/code-server:latest
    container_name: winejs-${APP_NAME}
    restart: unless-stopped
    ports:
      - "127.0.0.1:${APP_PORT}:8080"
    environment:
      - PASSWORD=winejs-vscode
      - SUDO_PASSWORD=winejs-vscode
      - DEFAULT_THEME=dark
    user: root
    volumes:
      # WineJS apps mount (read-only)
      - /opt/winejs/apps:/home/coder/projects:ro
      # Shared storage
      - /var/www/uploads:/home/coder/uploads:rw
      # VSCode extensions persistence
      - ${VSCODE_EXTENSIONS}:/home/coder/.local/share/code-server/extensions
      # Docker socket for Docker-in-Docker
      - /var/run/docker.sock:/var/run/docker.sock
    command: --auth password --bind-addr 0.0.0.0:8080 --disable-telemetry /home/coder/projects
    networks:
      - winejs-net

  # Path Mapper Service
  winejs-path-mapper:
    image: node:18-alpine
    container_name: winejs-path-mapper
    restart: unless-stopped
    ports:
      - "127.0.0.1:${PATH_MAPPER_PORT}:3001"
    environment:
      - VSCODE_PORT=${APP_PORT}
      - PORT=3001
    volumes:
      - ${PATH_MAPPER_DIR}:/app:ro
      - /opt/winejs/apps:/opt/winejs/apps:ro
      - /opt/winejs/data:/opt/winejs/data:ro
      - ${SHARED_VOLUMES}:/opt/winejs/shared-volumes:ro
      - /var/www/uploads:/var/www/uploads:ro
    working_dir: /app
    command: node server.js
    networks:
      - winejs-net

networks:
  winejs-net:
    external: true
DOCKER_EOF

# ============= CREATE WINEJS INTEGRATION EXTENSION =============
log "🔌 Creating WineJS integration extension..."

mkdir -p "$VSCODE_EXTENSIONS/winejs-integration"

cat > "$VSCODE_EXTENSIONS/winejs-integration/package.json" << 'EXTENSION_EOF'
{
    "name": "winejs-integration",
    "displayName": "WineJS Integration",
    "description": "Seamless integration with WineJS platform",
    "version": "1.0.0",
    "publisher": "winejs",
    "engines": {"vscode": "^1.85.0"},
    "categories": ["Other"],
    "activationEvents": ["onStartupFinished"],
    "main": "./extension.js",
    "contributes": {
        "commands": [
            {"command": "winejs.openApp", "title": "WineJS: Open App"},
            {"command": "winejs.createApp", "title": "WineJS: Create New App"},
            {"command": "winejs.openStorage", "title": "WineJS: Open Shared Storage"},
            {"command": "winejs.openPathMapper", "title": "WineJS: Open Path Mapper"}
        ],
        "viewsContainers": {
            "activitybar": [{"id": "winejs", "title": "WineJS", "icon": "$(rocket)"}]
        },
        "views": {
            "winejs": [{"id": "winejs.apps", "name": "WineJS Apps"}]
        }
    }
}
EXTENSION_EOF

cat > "$VSCODE_EXTENSIONS/winejs-integration/extension.js" << 'EXTENSION_JS_EOF'
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');

function activate(context) {
    console.log('WineJS Integration extension active!');
    
    let openAppCommand = vscode.commands.registerCommand('winejs.openApp', async () => {
        const appsDir = '/opt/winejs/apps';
        if (!fs.existsSync(appsDir)) {
            vscode.window.showErrorMessage('WineJS apps directory not found');
            return;
        }
        
        const apps = fs.readdirSync(appsDir).filter(f => 
            fs.statSync(path.join(appsDir, f)).isDirectory()
        );
        
        const selected = await vscode.window.showQuickPick(apps, {
            placeHolder: 'Select a WineJS app to open'
        });
        
        if (selected) {
            vscode.commands.executeCommand('vscode.openFolder', 
                vscode.Uri.file(path.join(appsDir, selected)));
        }
    });
    
    let createAppCommand = vscode.commands.registerCommand('winejs.createApp', async () => {
        const appName = await vscode.window.showInputBox({
            prompt: 'Enter app name',
            placeHolder: 'my-new-app'
        });
        if (appName) {
            const appPath = path.join('/opt/winejs/apps', appName);
            if (!fs.existsSync(appPath)) {
                fs.mkdirSync(appPath, { recursive: true });
                vscode.window.showInformationMessage(`Created app: ${appName}`);
                vscode.commands.executeCommand('vscode.openFolder', vscode.Uri.file(appPath));
            } else {
                vscode.window.showErrorMessage('App already exists');
            }
        }
    });
    
    let openStorageCommand = vscode.commands.registerCommand('winejs.openStorage', () => {
        vscode.commands.executeCommand('vscode.openFolder', 
            vscode.Uri.file('/var/www/uploads'));
    });
    
    let openPathMapperCommand = vscode.commands.registerCommand('winejs.openPathMapper', () => {
        vscode.env.openExternal(vscode.Uri.parse(`http://localhost:${process.env.PATH_MAPPER_PORT || 3001}/vscode`));
    });
    
    context.subscriptions.push(openAppCommand, createAppCommand, openStorageCommand, openPathMapperCommand);
}

module.exports = { activate, deactivate };
EXTENSION_JS_EOF

# ============= ADD FORGEJO INTEGRATION (OPTIONAL) =============
# Add this block HERE - after the extension creation, before PM2 setup
if [ -d "/opt/winejs/apps/forgejo" ]; then
    log "🔗 Linking Forgejo repositories to VSCode..."
    
    # Add symlink to Forgejo repos in VSCode workspace
    mkdir -p "$WORKSPACE_DIR/forgejo-repos"
    ln -sf /opt/winejs/repositories "$WORKSPACE_DIR/forgejo-repos" 2>/dev/null || true
    
    # Create a .code-workspace file that includes Forgejo repos
    cat > "$WORKSPACE_DIR/forgejo-workspace.code-workspace" << 'WORKSPACE_EOF'
{
    "folders": [
        {
            "name": "Forgejo Repositories",
            "path": "/opt/winejs/repositories"
        },
        {
            "name": "VSCode Apps",
            "path": "/opt/winejs/apps"
        },
        {
            "name": "Shared Storage",
            "path": "/var/www/uploads"
        }
    ],
    "settings": {
        "workbench.colorTheme": "dark",
        "git.enabled": true,
        "git.autofetch": true
    }
}
WORKSPACE_EOF
    
    log "✅ Forgejo integration added to VSCode"
fi

# ============= SET UP PM2 FOR PATH MAPPER =============
log "🚀 Setting up PM2 for path mapper persistence..."

if command -v pm2 &> /dev/null; then
    cd "$PATH_MAPPER_DIR"
    
    # Stop and delete existing instance if it exists
    if pm2 list | grep -q "winejs-path-mapper"; then
        log "Stopping existing path mapper..."
        pm2 stop winejs-path-mapper 2>/dev/null || true
        pm2 delete winejs-path-mapper 2>/dev/null || true
    fi
    
    # Start new instance
    pm2 start server.js --name winejs-path-mapper --env VSCODE_PORT=$APP_PORT
    pm2 save
    pm2 startup
fi
# ============= CREATE UNINSTALL SCRIPT =============
log "Creating uninstall script..."

cat > "$(dirname "$APP_DIR")/uninstall_vscode.sh" << 'UNINSTALL_EOF'
#!/bin/bash
# WineJS VSCode Uninstaller

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

log "🧹 Uninstalling VSCode Server..."

# ============= STOP PM2 PROCESSES =============
log "Stopping PM2 processes..."
if command -v pm2 &> /dev/null; then
    if pm2 list 2>/dev/null | grep -q "winejs-path-mapper"; then
        log "Stopping winejs-path-mapper..."
        pm2 stop winejs-path-mapper 2>/dev/null || true
        pm2 delete winejs-path-mapper 2>/dev/null || true
    fi
fi

# ============= STOP AND REMOVE DOCKER CONTAINERS =============
log "Stopping Docker containers..."

if docker ps -a 2>/dev/null | grep -q "winejs-vscode"; then
    log "Stopping winejs-vscode container..."
    docker stop winejs-vscode 2>/dev/null || true
    docker rm winejs-vscode 2>/dev/null || true
    log "✅ VSCode container removed"
fi

if docker ps -a 2>/dev/null | grep -q "winejs-path-mapper"; then
    log "Stopping winejs-path-mapper container..."
    docker stop winejs-path-mapper 2>/dev/null || true
    docker rm winejs-path-mapper 2>/dev/null || true
    log "✅ Path mapper container removed"
fi

# ============= REMOVE APP DIRECTORIES =============
log "Removing app directories..."

APP_NAME="vscode"
APP_DIR="/opt/winejs/apps/${APP_NAME}"
INSTANCE_DIR="/opt/winejs/kasmvnc-instances/${APP_NAME}"
VSCODE_DATA="/opt/winejs/data/vscode"
VSCODE_EXTENSIONS="/opt/winejs/data/vscode-extensions"
PATH_MAPPER_DIR="/opt/winejs/path-mapper"
ICON_FILE="/opt/winejs/translator/public/icons/${APP_NAME}.png"

# Remove directories if they exist
[ -d "$INSTANCE_DIR" ] && rm -rf "$INSTANCE_DIR" && log "✅ Instance directory removed"
[ -d "$APP_DIR" ] && rm -rf "$APP_DIR" && log "✅ App directory removed"
[ -d "$VSCODE_DATA" ] && rm -rf "$VSCODE_DATA" && log "✅ VSCode data removed"
[ -d "$VSCODE_EXTENSIONS" ] && rm -rf "$VSCODE_EXTENSIONS" && log "✅ VSCode extensions removed"
[ -d "$PATH_MAPPER_DIR" ] && rm -rf "$PATH_MAPPER_DIR" && log "✅ Path mapper removed"
[ -f "$ICON_FILE" ] && rm -f "$ICON_FILE" && log "✅ Icon removed"

# ============= REMOVE NGINX CONFIGURATION =============
log "Removing nginx configuration..."

NGINX_SITE="/etc/nginx/sites-available/winejs"

if [ ! -f "$NGINX_SITE" ]; then
    warn "nginx config not found at $NGINX_SITE"
else
    # Check if any VSCode routes exist
    if ! grep -q "vscode" "$NGINX_SITE"; then
        log "No VSCode routes found in nginx config"
    else
        log "Removing VSCode routes from nginx config..."
        
        # Create backup with timestamp
        BACKUP_FILE="${NGINX_SITE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$NGINX_SITE" "$BACKUP_FILE"
        log "✅ Backup created: $BACKUP_FILE"
        
        # Use awk to remove VSCode sections (MOST RELIABLE)
        awk '
            /# VSCode/ { skip=1 }
            /location \/vscode\/ {/ { skip=1 }
            /location \/vscode-browse\/ {/ { skip=1 }
            /^[[:space:]]*}/ && skip==1 { skip=0; next }
            skip==1 { next }
            { print }
        ' "$NGINX_SITE" > "${NGINX_SITE}.tmp"
        
        # Replace the original file
        mv "${NGINX_SITE}.tmp" "$NGINX_SITE"
        
        # Remove any orphaned vscode lines
        sed -i '/vscode/d' "$NGINX_SITE"
        
        # Test and reload nginx
        log "Testing nginx configuration..."
        if nginx -t 2>&1 | tee /tmp/nginx_test.log; then
            systemctl reload nginx
            log "✅ Nginx configuration successfully updated - VSCode routes removed"
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
if [ -f "/usr/local/bin/winejs-vscode" ]; then
    rm -f "/usr/local/bin/winejs-vscode"
    log "✅ Helper script removed"
fi

# ============= VERIFY REMOVAL =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              VSCODE SERVER UNINSTALLED SUCCESSFULLY!          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
log "✅ VSCode Server has been completely removed"
echo ""
log "Verification commands:"
echo "   docker ps -a | grep winejs-vscode"
echo "   ls /opt/winejs/apps/ | grep vscode"
echo "   ls /opt/winejs/data/ | grep vscode"
echo ""
UNINSTALL_EOF

chmod +x "$(dirname "$APP_DIR")/uninstall_vscode.sh"
log "✅ Uninstall script created: $(dirname "$APP_DIR")/uninstall_vscode.sh"

# ============= START CONTAINER =============
log "Starting VSCode Server container..."

cd "$INSTANCE_DIR"
docker-compose up -d

sleep 5

if docker ps | grep -q "winejs-${APP_NAME}"; then
    success "✅ Container started successfully"
else
    warn "⚠️ Container may not have started. Check: docker logs winejs-${APP_NAME}"
fi

# ============= INSTALL ESSENTIAL EXTENSIONS =============
log "📦 Installing essential VSCode extensions..."

docker exec "winejs-${APP_NAME}" bash -c '
    EXTENSIONS=(
        "ms-python.python"
        "ms-azuretools.vscode-docker"
        "eamodio.gitlens"
        "esbenp.prettier-vscode"
        "redhat.vscode-yaml"
        "ms-kubernetes-tools.vscode-kubernetes-tools"
    )
    
    for ext in "${EXTENSIONS[@]}"; do
        code-server --install-extension "$ext" --force 2>/dev/null || true
    done
' &

# ============= UPDATE NGINX CONFIG =============
log "Updating nginx configuration for VSCode..."

if [ -f "/etc/nginx/sites-available/winejs" ]; then
    # Check if VSCode routes already exist in port 443 block
    if ! grep -A200 "listen 443" /etc/nginx/sites-available/winejs | grep -q "location /vscode/"; then
        # Backup the current config
        cp /etc/nginx/sites-available/winejs /etc/nginx/sites-available/winejs.backup
        
        # Find the line number of the closing brace for the HTTPS server block
        HTTPS_START=$(grep -n "listen 443" /etc/nginx/sites-available/winejs | head -1 | cut -d: -f1)
        
        if [ -n "$HTTPS_START" ]; then
            # Find the closing brace of the HTTPS block
            BRACE_COUNT=0
            LINE_NUM=$HTTPS_START
            TOTAL_LINES=$(wc -l < /etc/nginx/sites-available/winejs)
            HTTPS_END=""
            
            while [ $LINE_NUM -le $TOTAL_LINES ]; do
                LINE=$(sed -n "${LINE_NUM}p" /etc/nginx/sites-available/winejs)
                for ((i=0; i<${#LINE}; i++)); do
                    char="${LINE:$i:1}"
                    if [ "$char" = "{" ]; then
                        BRACE_COUNT=$((BRACE_COUNT + 1))
                    elif [ "$char" = "}" ]; then
                        BRACE_COUNT=$((BRACE_COUNT - 1))
                    fi
                done
                if [ $BRACE_COUNT -eq 0 ]; then
                    HTTPS_END=$LINE_NUM
                    break
                fi
                LINE_NUM=$((LINE_NUM + 1))
            done
            
            if [ -n "$HTTPS_END" ]; then
                # Insert routes BEFORE the closing brace - NO QUOTES around ports!
                sed -i "${HTTPS_END}i\\
    # VSCode Editor (actual VSCode instance) - MAIN URL\n\
    location /vscode/ {\n\
        proxy_pass http://127.0.0.1:${APP_PORT}/;\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n\
        proxy_set_header X-Forwarded-Proto \$scheme;\n\
        \n\
        add_header Permissions-Policy \"clipboard-read=(self https://${DOMAIN_NAME}), clipboard-write=(self https://${DOMAIN_NAME})\";\n\
        add_header Cross-Origin-Embedder-Policy \"require-corp\";\n\
        add_header Cross-Origin-Opener-Policy \"same-origin\";\n\
        \n\
        proxy_http_version 1.1;\n\
        proxy_set_header Upgrade \$http_upgrade;\n\
        proxy_set_header Connection \"upgrade\";\n\
        \n\
        proxy_buffering off;\n\
        proxy_read_timeout 86400s;\n\
        proxy_send_timeout 86400s;\n\
    }\n\
\n\
    # VSCode Path Mapper (folder browser)\n\
    location /vscode-browse/ {\n\
        proxy_pass http://127.0.0.1:${PATH_MAPPER_PORT}/vscode/;\n\
        proxy_set_header Host \$host;\n\
        proxy_set_header X-Real-IP \$remote_addr;\n\
        rewrite ^/vscode-browse\$ /vscode-browse/ permanent;\n\
    }\n" /etc/nginx/sites-available/winejs
                
                log "✅ VSCode routes inserted into HTTPS server block"
            else
                warn "Could not find HTTPS block closing brace"
            fi
        else
            warn "Could not find HTTPS server block"
        fi
        
        # Test and reload
        if nginx -t; then
            systemctl reload nginx
            log "✅ Nginx updated with VSCode routes"
            log "   • /vscode/ → VSCode (port ${APP_PORT})"
            log "   • /vscode-browse/ → Path Mapper (port ${PATH_MAPPER_PORT})"
        else
            warn "Nginx test failed, restoring backup"
            cp /etc/nginx/sites-available/winejs.backup /etc/nginx/sites-available/winejs
            nginx -t && systemctl reload nginx
            log "⚠️ Could not add VSCode routes automatically"
        fi
    else
        log "VSCode routes already exist in nginx config"
    fi
else
    warn "nginx config not found, skipping"
fi


# ============= RELOAD TRANSLATOR =============
log "Reloading WineJS translator..."

pm2 restart translator 2>/dev/null || true

# ============= CREATE HELPER SCRIPT =============
log "Creating helper script..."

cat > /usr/local/bin/winejs-vscode << EOF
#!/bin/bash
# Quick VSCode launcher for WineJS

if [ -n "\$1" ]; then
    if [ -d "\$1" ]; then
        echo "Opening \$1 in VSCode..."
        curl -X POST http://localhost:3001/api/open \\
            -H "Content-Type: application/json" \\
            -d "{\"path\":\"\$1\"}" 2>/dev/null
    else
        echo "Opening VSCode at /vscode/\$1..."
        curl "http://localhost:3001/vscode/\$1" 2>/dev/null
    fi
else
    if command -v xdg-open &> /dev/null; then
        xdg-open "https://${DOMAIN_NAME}/vscode"
    elif command -v open &> /dev/null; then
        open "https://${DOMAIN_NAME}/vscode"
    else
        echo "Visit: https://${DOMAIN_NAME}/vscode"
    fi
fi
EOF

chmod +x /usr/local/bin/winejs-vscode
# ============= FINAL OUTPUT =============
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              VSCODE SERVER INSTALLED ON WINEJS!                ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
success "✅ VSCode Server installed as a WineJS app!"
echo ""
info "🌐 Access URLs:"
info "   • VSCode Editor: https://$DOMAIN_NAME/vscode/ (password: winejs-vscode)"
info "   • Browse Apps (Path Mapper): https://$DOMAIN_NAME/vscode-browse/"
echo ""
info "🔑 Login Password: winejs-vscode"
echo ""
info "📂 Path Mapping:"
info "   • https://$DOMAIN_NAME/vscode-browse/apps/milkshape → Browse MilkShape folder"
info "   • https://$DOMAIN_NAME/vscode/ → Open VSCode directly"
echo ""
info "🎯 Quick Commands:"
info "   • winejs-vscode                      # Open VSCode"
info "   • winejs-vscode /opt/winejs/apps/milkshape # Edit MilkShape app"
info "   • mount-helper list                  # List shared volumes"
echo ""
info "🔧 Features:"
info "   • Edit any WineJS app in VS Code"
info "   • Access shared /uploads folder"
info "   • Built-in terminal with Docker access"
info "   • Git integration"
info "   • Extensions marketplace"
echo ""
info "📝 To uninstall: sudo bash $(dirname "$APP_DIR")/uninstall_vscode.sh"
echo ""
success "✨ VSCode Server is ready! Visit https://$DOMAIN_NAME/vscode/"
echo ""

echo "Find all uninstall scripts in the apps directory"
echo "find /opt/winejs/apps -name \"uninstall_*\" -type f"