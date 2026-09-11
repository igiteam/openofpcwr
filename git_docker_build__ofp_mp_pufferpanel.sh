#!/bin/bash

# Configuration
LOGO_URL="https://cdn.gitgpt.chat/rtx/images/mumble-voip-logo.png"
REPO_URL="https://github.com/igiteam/openofp"
YOUR_GITHUB_USERNAME="igiteam"
NEW_REPO_NAME="openofp"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}🚀 OpenOFP Server Docker Setup${NC}"
echo "================================================"

# Check gh CLI
if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠️ Installing GitHub CLI...${NC}"
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt update && sudo apt install gh
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install gh
    else
        echo -e "${RED}❌ Install gh manually: https://cli.github.com/${NC}"
        exit 1
    fi
fi

# Login check
if ! gh auth status &> /dev/null; then
    echo -e "${YELLOW}🔐 Login to GitHub:${NC}"
    gh auth login
fi

# Delete existing repo if exists
echo -e "\n${GREEN}📦 Setting up repository...${NC}"
if gh repo view "$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME" &> /dev/null; then
    echo -e "${YELLOW}⚠️ Repository exists, deleting...${NC}"
    echo "y" | gh repo delete "$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME"
    sleep 3
fi

# Create new repository
gh repo create "$NEW_REPO_NAME" --public --description "OpenOFP - Operation Flashpoint Dedicated Server with Docker"

# Clone
echo -e "\n${GREEN}📥 Cloning OpenOFP repository...${NC}"
git clone "$REPO_URL" "$NEW_REPO_NAME"
cd "$NEW_REPO_NAME"

# Change remote
git remote remove origin
git remote add origin "https://github.com/$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME.git"

# ============================================
# CREATE DOCKERFILE FOR OFP SERVER
# ============================================
echo -e "${GREEN}🐳 Creating Dockerfile.server...${NC}"
cat > Dockerfile.server << 'EOF'
FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get install -y \
    cmake git clang build-essential \
    libsdl3-dev libopenal-dev libogg-dev \
    libvorbis-dev libopus-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY . .

RUN mkdir build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=Release \
             -DCWR_BUILD_SERVER=ON \
             -DCWR_BUILD_GAME=OFF \
             -DCWR_BUILD_TOOLS=OFF && \
    cmake --build . --target Server -j$(nproc)

FROM ubuntu:22.04
RUN apt-get update && apt-get install -y \
    libsdl3-0 libopenal1 libogg0 libvorbis0a libopus0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/build/apps/cwr/Server/Server /usr/local/bin/ofp-server

EXPOSE 2302 2302/udp 2303/udp
VOLUME ["/data"]
WORKDIR /data

ENTRYPOINT ["/usr/local/bin/ofp-server"]
CMD ["--config", "/data/server.cfg"]
EOF

# ============================================
# CREATE GITHUB ACTIONS WORKFLOW
# ============================================
echo -e "${GREEN}⚙️ Creating GitHub Actions workflow...${NC}"
mkdir -p .github/workflows
cat > .github/workflows/ofp-server.yml << 'EOF'
name: Build OFP Server Image

on:
  workflow_dispatch:

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ofp-server

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3
      
      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          file: Dockerfile.server
          platforms: linux/amd64
          push: true
          tags: |
            ghcr.io/${{ github.repository }}/ofp-server:latest
            ghcr.io/${{ github.repository }}/ofp-server:${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
EOF

# ============================================
# CREATE PUFFERPANEL JSON TEMPLATE
# ============================================
echo -e "${GREEN}📝 Creating ofp_mp_server_pufferpanel.json...${NC}"
cat > ofp_mp_server_pufferpanel.json << EOF
{
  "name": "OpenOFP Multiplayer Server",
  "type": "docker",
  "image": "ghcr.io/$YOUR_GITHUB_USERNAME/openofp/ofp-server:latest",
  "description": "Operation Flashpoint dedicated server for PufferPanel",
  "ports": {
    "game": {
      "internal": 2302,
      "external": 2302,
      "protocol": "tcp"
    },
    "voice": {
      "internal": 2303,
      "external": 2303,
      "protocol": "udp"
    }
  },
  "environment": [
    {
      "key": "SERVER_NAME",
      "value": "OpenOFP Server",
      "description": "Server display name"
    },
    {
      "key": "MAX_PLAYERS",
      "value": "32",
      "description": "Maximum player count"
    },
    {
      "key": "MISSION",
      "value": "coop_basic",
      "description": "Mission file name"
    }
  ],
  "volumes": [
    {
      "container": "/data",
      "description": "Server data directory"
    }
  ],
  "executable": "ofp-server",
  "startup_command": "--config /data/server.cfg --server-name \\${SERVER_NAME} --max-players \\${MAX_PLAYERS} --mission \\${MISSION}",
  "stop_command": "quit",
  "supported_architectures": ["linux/amd64"],
  "minimum_requirements": {
    "cpu": 1,
    "memory": 512,
    "disk": 1024
  }
}
EOF

# ============================================
# CREATE DEFAULT SERVER CONFIG
# ============================================
echo -e "${GREEN}📝 Creating default server.cfg...${NC}"
cat > server.cfg << 'EOF'
// OpenOFP Server Configuration

// Server Identity
serverName = "OpenOFP Server";
password = "";
passwordAdmin = "admin123";
reportingIP = "master.openofp.com";

// Game Settings
maxPlayers = 32;
kickDuplicate = 1;
voteThreshold = 0.5;
voteMissionPlayers = 3;

// Mission Settings
class Missions {
    class Coop_Basic {
        template = "coop_basic.Demo";
        difficulty = "veteran";
    };
};

// Network Settings
maxBandwidth = 10240;
minBandwidth = 5120;
pingInterval = 30;

// Logging
logFile = "server.log";
EOF

# ============================================
# .dockerignore
# ============================================
cat > .dockerignore << 'EOF'
.git/
.github/
build/
target/
*.md
LICENSE
EOF

# ============================================
# PUSH TO GITHUB
# ============================================
echo -e "\n${GREEN}💾 Committing and pushing...${NC}"
git add .
git commit -m "Add OFP server Docker build + PufferPanel template"
git branch -M main
git push -u origin main

echo -e "\n${GREEN}✅ Setup complete!${NC}"
echo "================================================"

# Open Actions page
echo -e "${BLUE}📊 Opening GitHub Actions...${NC}"
sleep 2
open "https://github.com/$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME/actions" 2>/dev/null || \
xdg-open "https://github.com/$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME/actions" 2>/dev/null || \
echo "Open: https://github.com/$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME/actions"

# Ask to trigger build
echo -e "\n${YELLOW}Trigger Docker build now? (y/n): ${NC}"
read -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}🚀 Triggering build...${NC}"
    gh workflow run ofp-server.yml --repo "$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME"
    echo -e "\n${GREEN}✅ Build triggered!${NC}"
else
    echo -e "\n${YELLOW}Later: gh workflow run ofp-server.yml --repo $YOUR_GITHUB_USERNAME/$NEW_REPO_NAME${NC}"
fi

echo -e "\n${GREEN}🎯 Docker image:${NC}"
echo "ghcr.io/$YOUR_GITHUB_USERNAME/$NEW_REPO_NAME/ofp-server:latest"

echo -e "\n${BLUE}📋 PufferPanel setup:${NC}"
echo "1. Login to PufferPanel"
echo "2. Create New Server"
echo "3. Import ofp_mp_server_pufferpanel.json"
echo "4. Deploy!"

echo -e "\n${GREEN}✅ Done!${NC}"

# What This Does
# File	Purpose
# Dockerfile.server	Builds OFP server binary
# ofp-server.yml	GitHub Actions (manual trigger)
# ofp_mp_server_pufferpanel.json	PufferPanel template
# server.cfg	Default config
# .dockerignore	Excludes build files