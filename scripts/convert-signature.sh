#!/bin/bash
# convert-signature.sh
# 将 Android JKS 签名转换为 VelaJS 快应用所需的 PEM 格式
#
# 用法: ./scripts/convert-signature.sh <keystore.jks> [alias] [password]
#
# 需要: keytool (JDK), openssl

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WATCH_SIGN_DIR="$PROJECT_ROOT/watch-app/sign"

JKS_FILE="${1:-}"
ALIAS="${2:-}"
PASSWORD="${3:-}"

if [ -z "$JKS_FILE" ]; then
    echo "用法: $0 <keystore.jks> [alias] [password]"
    echo ""
    echo "参数:"
    echo "  keystore.jks  - Android 签名文件路径"
    echo "  alias         - 密钥别名 (可选，默认使用第一个)"
    echo "  password      - 密钥库密码 (可选，会交互式询问)"
    exit 1
fi

if [ ! -f "$JKS_FILE" ]; then
    echo "错误: 找不到文件 $JKS_FILE"
    exit 1
fi

# 创建输出目录
mkdir -p "$WATCH_SIGN_DIR/debug"
mkdir -p "$WATCH_SIGN_DIR/release"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo "=== Step 1: JKS → P12 ==="
P12_FILE="$TEMP_DIR/keystore.p12"

if [ -n "$ALIAS" ] && [ -n "$PASSWORD" ]; then
    keytool -importkeystore \
        -srckeystore "$JKS_FILE" \
        -srcstoretype jks \
        -srcstorepass "$PASSWORD" \
        -srcalias "$ALIAS" \
        -destkeystore "$P12_FILE" \
        -deststoretype pkcs12 \
        -deststorepass "$PASSWORD" \
        -destalias "$ALIAS"
else
    echo "请输入 JKS 密码（如已设置 alias 可能需要输入 alias 密码）:"
    keytool -importkeystore \
        -srckeystore "$JKS_FILE" \
        -destkeystore "$P12_FILE" \
        -srcstoretype jks \
        -deststoretype pkcs12
fi

echo ""
echo "=== Step 2: P12 → PEM ==="
PEM_FILE="$TEMP_DIR/keystore.pem"

if [ -n "$PASSWORD" ]; then
    openssl pkcs12 -nodes -in "$P12_FILE" -out "$PEM_FILE" -passin pass:"$PASSWORD"
else
    echo "请输入 P12 密码（通常与 JKS 密码相同）:"
    openssl pkcs12 -nodes -in "$P12_FILE" -out "$PEM_FILE"
fi

echo ""
echo "=== Step 3: 提取私钥和证书 ==="

# 提取私钥
PRIVATE_KEY="$TEMP_DIR/private.pem"
awk '/-----BEGIN PRIVATE KEY-----/,/-----END PRIVATE KEY-----/' "$PEM_FILE" > "$PRIVATE_KEY"

# 提取证书
CERTIFICATE="$TEMP_DIR/certificate.pem"
awk '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/' "$PEM_FILE" > "$CERTIFICATE"

if [ ! -s "$PRIVATE_KEY" ] || [ ! -s "$CERTIFICATE" ]; then
    echo "错误: 提取私钥或证书失败"
    echo "请尝试使用在线工具: https://cdn.hybrid.xiaomi.com/aiot-ide/signature-generate-tool/v2/index.html"
    exit 1
fi

# 复制到 debug 和 release 目录
cp "$PRIVATE_KEY" "$WATCH_SIGN_DIR/debug/private.pem"
cp "$CERTIFICATE" "$WATCH_SIGN_DIR/debug/certificate.pem"
cp "$PRIVATE_KEY" "$WATCH_SIGN_DIR/release/private.pem"
cp "$CERTIFICATE" "$WATCH_SIGN_DIR/release/certificate.pem"

echo ""
echo "=== 完成! ==="
echo "签名文件已生成到:"
echo "  Debug:   $WATCH_SIGN_DIR/debug/"
echo "  Release: $WATCH_SIGN_DIR/release/"
echo ""
echo "包含文件:"
echo "  - private.pem    (私钥)"
echo "  - certificate.pem (证书)"
