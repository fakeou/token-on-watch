#!/bin/bash
# setup-flutter-android.sh
# 一键安装 Flutter + Android SDK（最小化方案）
# 需要 Homebrew 已安装

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Token Monitor - Flutter 环境安装脚本 ===${NC}"
echo ""

# ──────────────────────────────────────
# Step 1: 安装 Java (OpenJDK 17)
# ──────────────────────────────────────
echo -e "${YELLOW}[1/5] 安装 OpenJDK 17...${NC}"
if brew list --cask temurin@17 &>/dev/null; then
    echo "  已安装，跳过"
else
    brew install --cask temurin@17
fi

# 配置 JAVA_HOME
JAVA_HOME_PATH=$(/usr/libexec/java_home -v 17 2>/dev/null || echo "")
if [ -n "$JAVA_HOME_PATH" ]; then
    echo "  JAVA_HOME: $JAVA_HOME_PATH"
    export JAVA_HOME="$JAVA_HOME_PATH"
else
    echo -e "  ${RED}Java 安装可能失败，请手动检查${NC}"
fi

# ──────────────────────────────────────
# Step 2: 安装 Android 命令行工具
# ──────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/5] 安装 Android 命令行工具...${NC}"

ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_HOME

if [ -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
    echo "  已安装，跳过"
else
    # 下载 cmdline-tools
    CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip"
    TEMP_DIR=$(mktemp -d)
    
    echo "  下载中..."
    curl -L -o "$TEMP_DIR/cmdline-tools.zip" "$CMDLINE_TOOLS_URL"
    
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    unzip -qo "$TEMP_DIR/cmdline-tools.zip" -d "$TEMP_DIR"
    mv "$TEMP_DIR/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
    rm -rf "$TEMP_DIR"
    echo "  命令行工具安装完成"
fi

# ──────────────────────────────────────
# Step 3: 用 sdkmanager 安装 SDK 组件
# ──────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/5] 安装 Android SDK 组件...${NC}"

SDKMANAGER="$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"

# 接受许可证
yes | "$SDKMANAGER" --licenses > /dev/null 2>&1 || true

# 安装必要组件
"$SDKMANAGER" "platform-tools" "platforms;android-34" "build-tools;34.0.0"
echo "  SDK 组件安装完成"

# ──────────────────────────────────────
# Step 4: 安装 Flutter
# ──────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/5] 安装 Flutter SDK...${NC}"

if which flutter &>/dev/null; then
    echo "  已安装，跳过"
else
    brew install flutter
    echo "  Flutter 安装完成"
fi

# ──────────────────────────────────────
# Step 5: 配置环境变量
# ──────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/5] 配置环境变量...${NC}"

SHELL_RC="$HOME/.zshrc"
ENV_BLOCK='# === Token Monitor - Android/Flutter 环境 ===
export JAVA_HOME=$('"'"'/usr/libexec/java_home -v 17'"'"')
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
# === End ==='

# 检查是否已配置
if grep -q "Token Monitor - Android/Flutter" "$SHELL_RC" 2>/dev/null; then
    echo "  环境变量已配置，跳过"
else
    echo "" >> "$SHELL_RC"
    echo "$ENV_BLOCK" >> "$SHELL_RC"
    echo "  环境变量已写入 $SHELL_RC"
fi

# 当前 session 也设置
export JAVA_HOME=$('/usr/libexec/java_home -v 17')
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# ──────────────────────────────────────
# 验证
# ──────────────────────────────────────
echo ""
echo -e "${GREEN}=== 安装完成，验证结果 ===${NC}"
echo ""

echo "Java:"
java -version 2>&1 | head -1
echo ""

echo "Flutter:"
flutter --version 2>&1 | head -3
echo ""

echo "Android SDK:"
echo "  ANDROID_HOME=$ANDROID_HOME"
echo "  sdkmanager: $([ -f "$SDKMANAGER" ] && echo 'OK' || echo 'MISSING')"
echo ""

echo "Flutter doctor:"
flutter doctor 2>&1
echo ""

echo -e "${GREEN}=== 安装完成! ===${NC}"
echo ""
echo "下一步："
echo "  1. 重启终端（或执行 source ~/.zshrc）"
echo "  2. cd /Users/ousu/Documents/work/token-monitor/phone-app"
echo "  3. flutter pub get"
echo "  4. flutter run"
