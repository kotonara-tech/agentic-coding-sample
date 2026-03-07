#!/usr/bin/bash

# Post-create script for Claude Code devcontainer environment
# Runs setup.sh with devcontainer-specific configurations

set -e

echo "Starting devcontainer environment initialization..."

echo "Installing UV (Universal Version Manager) for Spec-Kit installation..."
curl -LsSf https://astral.sh/uv/install.sh | sh

# Load .env if present (fallback when runArgs --env-file is not used)
if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
    echo "Loaded environment variables from .env"
    # Persist to bashrc for interactive sessions
    if ! grep -q 'source.*\.env' "$HOME/.bashrc" 2>/dev/null; then
        echo '[[ -f "$OLDPWD/.env" ]] && set -a && source "$OLDPWD/.env" && set +a' >> "$HOME/.bashrc"
    fi
fi

# Add ~/.local/bin to PATH before Claude Code installation
# This prevents the "not in PATH" warning from Claude install script
export PATH="$HOME/.local/bin:$PATH"

# Persist PATH update to bashrc for future sessions
if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    echo " Added $HOME/.local/bin to PATH in .bashrc"
fi

echo " Installing Node.js and npx..."
if ! command -v npx &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo "    Node.js and npx installed successfully"
    echo "    Node version: $(node --version)"
    echo "    npm version: $(npm --version)"
    echo "    npx version: $(npx --version)"
else
    echo "    npx already installed: $(npx --version)"
fi

echo " Installing Claude Code CLI..."
if ! command -v claude &> /dev/null; then
    echo "   Downloading from https://claude.ai/install.sh"
    if curl -fsSL https://claude.ai/install.sh | bash; then
        echo "    Claude Code CLI installed successfully"
        echo "    Location: $HOME/.local/bin/claude"
        if command -v claude &> /dev/null; then
            echo "    Version: $(claude --version 2>&1 || echo 'version check failed')"
        fi
    else
        echo "     Warning: Claude Code CLI installation failed"
        echo "   The devcontainer will continue, but Claude Code may not be available"
    fi
else
    echo "    Claude Code CLI already installed"
    echo "    Version: $(claude --version 2>&1 || echo 'version check failed')"
fi

# Configure user-level Claude settings for --dangerously-skip-permissions
CLAUDE_USER_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
if [ ! -f "$CLAUDE_USER_SETTINGS" ]; then
    echo '{"dangerouslySkipPermissions": true}' > "$CLAUDE_USER_SETTINGS"
    echo "Created $CLAUDE_USER_SETTINGS with dangerouslySkipPermissions=true"
else
    # Inject dangerouslySkipPermissions if not already present
    if ! grep -q '"dangerouslySkipPermissions"' "$CLAUDE_USER_SETTINGS"; then
        # Use python3 to safely merge JSON
        python3 -c "
import json, sys
with open('$CLAUDE_USER_SETTINGS') as f:
    cfg = json.load(f)
cfg['dangerouslySkipPermissions'] = True
with open('$CLAUDE_USER_SETTINGS', 'w') as f:
    json.dump(cfg, f, indent=2)
print('Updated $CLAUDE_USER_SETTINGS with dangerouslySkipPermissions=true')
"
    else
        echo "dangerouslySkipPermissions already set in $CLAUDE_USER_SETTINGS"
    fi
fi

echo ""
echo "Ready for Claude Code development!"
echo "claude --dangerously-skip-permissions is enabled by default via settings.json"

echo "Installing Spec-Kit"
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git
