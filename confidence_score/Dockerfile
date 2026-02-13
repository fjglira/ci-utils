# OSSM Release Confidence Score Container
# Uses Debian base with Claude Code CLI + Google Cloud authentication for Red Hat/Vertex AI setup

FROM debian:bookworm-slim

# Install required dependencies
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    ca-certificates \
    jq \
    git \
    python3 \
    python3-pip \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Install Google Cloud CLI (required for Red Hat Vertex AI setup)
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | sh

# Ensure Claude CLI and gcloud are in PATH
ENV PATH="/root/.local/bin:${PATH}"

# Set up Red Hat Vertex AI environment variables
ENV CLAUDE_CODE_USE_VERTEX=1
ENV CLOUD_ML_REGION=us-east5
ENV REPORTPORTAL_PROJECT="osssm_general"

# Repository configuration for fetching latest prompts
ENV CI_UTILS_REPO_URL="https://github.com/fjglira/ci-utils"
ENV CI_UTILS_BRANCH="add-claude-container"

# Create secure directories for secrets (GCP service account key)
RUN mkdir -p /run/secrets \
    && chmod 700 /run/secrets

# Create configuration directories
RUN mkdir -p /root/.config/claude \
    && mkdir -p /root/.config/gcloud

# Copy configuration and scripts
COPY claude-config-vertex.json /root/.config/claude/config.json
COPY run-confidence-score.sh /app/run-confidence-score.sh

# Make scripts executable
RUN chmod +x /app/run-confidence-score.sh

# Install git for repo fetching (if not already installed)
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Set default working directory
WORKDIR /app

# Health check to ensure Claude CLI is working with Vertex AI
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD claude --version && gcloud --version || exit 1

# Default command
CMD ["/app/run-confidence-score.sh"]

# Labels for documentation
LABEL maintainer="Francisco Herrera"
LABEL description="OSSM Release Confidence Score Calculator using Claude Code CLI + Red Hat Vertex AI"
LABEL version="2.0"
LABEL project="OSSM-11131"
LABEL auth_method="vertex_ai"