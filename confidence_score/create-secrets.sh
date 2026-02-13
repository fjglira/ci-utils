#!/bin/bash

# OSSM Confidence Score - Secure Secret File Creator (Red Hat Vertex AI)
# Creates secret files with proper permissions for container usage

set -e

SECRETS_DIR="./secrets"

echo "=== OSSM Confidence Score Secret Setup (Red Hat Vertex AI) ==="
echo ""

# Create secrets directory
if [ ! -d "$SECRETS_DIR" ]; then
    mkdir -p "$SECRETS_DIR"
    echo "✅ Created secrets directory: $SECRETS_DIR"
else
    echo "📁 Secrets directory already exists: $SECRETS_DIR"
fi

# Function to copy and secure a file
copy_secret_file() {
    local secret_name="$1"
    local secret_file="$SECRETS_DIR/$2"
    local prompt_msg="$3"

    if [ -f "$secret_file" ]; then
        echo "⚠️  Secret file already exists: $secret_file"
        read -p "Overwrite? (y/N): " -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            echo "   Skipping $secret_name"
            return
        fi
    fi

    echo ""
    echo "📝 $prompt_msg"
    read -p "Enter path to file: " -r source_file

    if [ ! -f "$source_file" ]; then
        echo "❌ File not found: $source_file"
        return
    fi

    # Copy file with secure permissions
    cp "$source_file" "$secret_file"
    chmod 600 "$secret_file"
    echo "✅ Created $secret_name: $secret_file"
}

# Function to create a text secret file
create_secret_file() {
    local secret_name="$1"
    local secret_file="$SECRETS_DIR/$2"
    local prompt_msg="$3"

    if [ -f "$secret_file" ]; then
        echo "⚠️  Secret file already exists: $secret_file"
        read -p "Overwrite? (y/N): " -r overwrite
        if [[ ! $overwrite =~ ^[Yy]$ ]]; then
            echo "   Skipping $secret_name"
            return
        fi
    fi

    echo ""
    echo "📝 $prompt_msg"
    read -s -p "Enter value: " secret_value
    echo ""

    if [ -z "$secret_value" ]; then
        echo "❌ Empty value provided. Skipping $secret_name"
        return
    fi

    # Write secret to file with secure permissions
    echo "$secret_value" > "$secret_file"
    chmod 600 "$secret_file"
    echo "✅ Created $secret_name: $secret_file"

    # Clear variable from memory
    unset secret_value
}

# Create GCP Service Account Key secret
copy_secret_file "GCP Service Account Key" "gcp-sa-key.json" "GCP Service Account Key JSON file (same one you use for Claude Code setup)"

# Ask about Report Portal secrets
echo ""
read -p "Do you want to configure Report Portal secrets? (y/N): " -r configure_rp
if [[ $configure_rp =~ ^[Yy]$ ]]; then
    create_secret_file "Report Portal URL" "reportportal_url" "Report Portal URL (e.g., https://your-reportportal.com)"
    create_secret_file "Report Portal Token" "reportportal_token" "Report Portal authentication token"
fi

echo ""
echo "=== Secret Setup Complete ==="
echo ""
echo "Created files:"
ls -la "$SECRETS_DIR/" 2>/dev/null || echo "No secret files created"

echo ""
echo "Usage example:"
echo "  docker run --rm \\"
if [ -f "$SECRETS_DIR/gcp-sa-key.json" ]; then
    echo "    --mount type=bind,source=\"\$(pwd)/secrets/gcp-sa-key.json\",target=/run/secrets/gcp_service_account_key,readonly \\"
fi
if [ -f "$SECRETS_DIR/reportportal_url" ]; then
    echo "    --mount type=bind,source=\"\$(pwd)/secrets/reportportal_url\",target=/run/secrets/reportportal_url,readonly \\"
fi
if [ -f "$SECRETS_DIR/reportportal_token" ]; then
    echo "    --mount type=bind,source=\"\$(pwd)/secrets/reportportal_token\",target=/run/secrets/reportportal_token,readonly \\"
fi
echo "    -e GCP_PROJECT_ID=\"your-team-project-id\" \\"
echo "    -e BUILD_ID=\"OSSM-3.1.0-RC1\" \\"
echo "    -e CHANGE_TYPE=\"FULL\" \\"
echo "    -v \$(pwd)/reports:/app/reports \\"
echo "    quay.io/your-org/ossm-confidence:latest"

echo ""
echo "🔒 Security notes:"
echo "  - Secret files have 600 permissions (owner read/write only)"
echo "  - Add 'secrets/' to your .gitignore to prevent accidental commits"
echo "  - This uses the same GCP service account as your Claude Code CLI setup"
echo "  - Get your GCP_PROJECT_ID from ~/.bashrc, ~/.zshrc, or the Red Hat spreadsheet"
echo "  - Consider using your CI/CD system's secret management instead"