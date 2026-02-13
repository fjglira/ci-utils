# Quick Setup Guide

## 1. Configure Repository URL

Update the repository URL to point to your actual ci-utils repository:

```bash
# Option 1: Set environment variables
export CI_UTILS_REPO_URL="https://github.com/your-org/ci-utils.git"
export CI_UTILS_BRANCH="main"  # or your branch name

# Option 2: Edit .env file
cp .env.template .env
# Edit .env and update CI_UTILS_REPO_URL with your actual repository
```

## 2. Set Up Secrets

```bash
# Run the interactive secret setup
./create-secrets.sh

# Or manually create secrets
mkdir -p secrets
cp /path/to/your-gcp-service-account.json secrets/gcp-sa-key.json
chmod 600 secrets/gcp-sa-key.json
```

## 3. Find Your GCP Project ID

```bash
# Check your Claude CLI configuration
grep ANTHROPIC_VERTEX_PROJECT_ID ~/.bashrc ~/.zshrc

# Or check current gcloud project
gcloud config get-value project
```

## 4. Build and Test

```bash
# Build the container
./build.sh

# Test with your configuration
docker run --rm \
  --mount type=bind,source="$(pwd)/secrets/gcp-sa-key.json",target=/run/secrets/gcp_service_account_key,readonly \
  -e GCP_PROJECT_ID="your-team-project-id" \
  -e CI_UTILS_REPO_URL="https://github.com/your-org/ci-utils.git" \
  -e BUILD_ID="OSSM-3.1.0-RC1" \
  -e CHANGE_TYPE="FULL" \
  -v $(pwd)/reports:/app/reports \
  ossm-confidence:latest
```

## 5. Deploy to Quay.io

```bash
# Tag and push to your registry
./build.sh push
```

## Repository Configuration Notes

- The container fetches `ai-helpers/ossm-release-confidence.md` at runtime
- If the repository is unreachable, it falls back to a built-in methodology
- This ensures your analysis always uses the latest methodology without rebuilding the container
- Perfect for CI environments where methodology updates happen frequently