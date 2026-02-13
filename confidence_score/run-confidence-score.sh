#!/bin/bash

# OSSM Release Confidence Score Runner
# This script initializes Claude Code CLI with Red Hat Vertex AI and runs the confidence score analysis
# Security: Handles GCP service account keys as secrets without exposure

set -e

echo "=== OSSM Release Confidence Score Calculator ==="
echo "Jira Epic: OSSM-11131"
echo "Owner: Francisco Herrera"
echo "Authentication: Red Hat Vertex AI (Google Cloud)"
echo ""

# Cleanup function to remove any temporary files with secrets
cleanup() {
    rm -f /tmp/claude-config-temp.json /app/current-analysis-prompt.txt /tmp/gcp-sa-key.json /tmp/methodology-content.md
    rm -rf /tmp/ci-utils-repo
}
trap cleanup EXIT

# Check required secrets and environment variables
check_requirements() {
    local missing_items=()

    # Check for GCP service account key
    if [ ! -f "/run/secrets/gcp_service_account_key" ] && [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
        missing_items+=("GCP Service Account Key (secret file or GOOGLE_APPLICATION_CREDENTIALS)")
    fi

    # Check for required GCP project ID
    if [ -z "$ANTHROPIC_VERTEX_PROJECT_ID" ] && [ -z "$GCP_PROJECT_ID" ]; then
        missing_items+=("ANTHROPIC_VERTEX_PROJECT_ID or GCP_PROJECT_ID")
    fi

    # Check build information
    if [ -z "$BUILD_ID" ] && [ -z "$RELEASE_CANDIDATE" ]; then
        missing_items+=("BUILD_ID or RELEASE_CANDIDATE")
    fi

    # Check change type
    if [ -z "$CHANGE_TYPE" ]; then
        missing_items+=("CHANGE_TYPE (FULL/CORE/BASIC)")
    fi

    if [ ${#missing_items[@]} -ne 0 ]; then
        echo "❌ Missing required parameters:"
        printf "   - %s\n" "${missing_items[@]}"
        echo ""
        echo "Required parameters for Red Hat Vertex AI setup:"
        echo "  GCP Auth: Mount service account key at /run/secrets/gcp_service_account_key"
        echo "  GCP_PROJECT_ID: Your team's GCP project ID (from Red Hat spreadsheet)"
        echo "  BUILD_ID: Build ID to analyze (or use RELEASE_CANDIDATE)"
        echo "  CHANGE_TYPE: Type of changes (FULL/CORE/BASIC)"
        echo ""
        echo "Optional parameters:"
        echo "  OSSM_VERSION: OSSM version being tested (default: auto-detect)"
        echo "  CONFIDENCE_THRESHOLD: Target confidence threshold (default: 8)"
        echo "  TESTING_STAGE: Specific stage focus (upstream/midstream/downstream)"
        echo "  Report Portal secrets: /run/secrets/reportportal_url, /run/secrets/reportportal_token"
        echo ""
        echo "Secure usage example:"
        echo "  docker run --rm \\"
        echo "    --mount type=bind,source=./secrets/gcp-sa-key.json,target=/run/secrets/gcp_service_account_key,readonly \\"
        echo "    -e GCP_PROJECT_ID=your-team-project-id \\"
        echo "    -e BUILD_ID=OSSM-3.1.0-RC1 -e CHANGE_TYPE=FULL \\"
        echo "    ossm-confidence:latest"
        echo ""
        echo "Note: Get your GCP project ID from the Red Hat spreadsheet mentioned in the Claude setup guide."
        exit 1
    fi
}

# Set up GCP authentication and Vertex AI configuration
setup_gcp_auth() {
    echo "🔧 Setting up Google Cloud authentication for Red Hat Vertex AI..."

    # Set project ID (prioritize GCP_PROJECT_ID if provided)
    if [ -n "$GCP_PROJECT_ID" ]; then
        export ANTHROPIC_VERTEX_PROJECT_ID="$GCP_PROJECT_ID"
    fi

    echo "  Project ID: $ANTHROPIC_VERTEX_PROJECT_ID"
    echo "  Region: $CLOUD_ML_REGION"

    # Handle service account key authentication
    if [ -f "/run/secrets/gcp_service_account_key" ]; then
        echo "✅ GCP service account key loaded from secret file"
        export GOOGLE_APPLICATION_CREDENTIALS="/run/secrets/gcp_service_account_key"
    elif [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
        echo "✅ Using GOOGLE_APPLICATION_CREDENTIALS environment variable"
    else
        echo "❌ No GCP authentication method found"
        exit 1
    fi

    # Authenticate with Google Cloud
    echo "🔐 Authenticating with Google Cloud..."
    if ! gcloud auth activate-service-account --key-file="$GOOGLE_APPLICATION_CREDENTIALS" >/dev/null 2>&1; then
        echo "❌ GCP authentication failed. Check your service account key."
        exit 1
    fi

    # Set the project
    if ! gcloud config set project "$ANTHROPIC_VERTEX_PROJECT_ID" >/dev/null 2>&1; then
        echo "❌ Failed to set GCP project. Check your project ID."
        exit 1
    fi

    # Set quota project for Vertex AI billing
    if ! gcloud auth application-default set-quota-project cloudability-it-gemini >/dev/null 2>&1; then
        echo "⚠️  Warning: Could not set quota project. This might affect billing."
    fi

    echo "✅ Google Cloud authentication successful"
}

# Securely read secrets (Report Portal only, since GCP auth is handled separately)
read_secrets() {
    # Read Report Portal secrets if available
    if [ -f "/run/secrets/reportportal_url" ]; then
        REPORTPORTAL_URL_VALUE=$(cat /run/secrets/reportportal_url)
        echo "✅ Report Portal URL loaded from secret file"
    elif [ -n "$REPORTPORTAL_URL" ]; then
        REPORTPORTAL_URL_VALUE="$REPORTPORTAL_URL"
    fi

    if [ -f "/run/secrets/reportportal_token" ]; then
        REPORTPORTAL_TOKEN_VALUE=$(cat /run/secrets/reportportal_token)
        echo "✅ Report Portal token loaded from secret file"
    elif [ -n "$REPORTPORTAL_TOKEN" ]; then
        REPORTPORTAL_TOKEN_VALUE="$REPORTPORTAL_TOKEN"
        # Clear the environment variable to prevent exposure
        unset REPORTPORTAL_TOKEN
    fi
}

# Initialize Claude configuration for Vertex AI
init_claude_config() {
    echo "🔧 Initializing Claude CLI for Vertex AI..."

    # Create temporary config with secrets substituted
    cp /root/.config/claude/config.json /tmp/claude-config-temp.json

    # Replace Report Portal placeholders if available
    if [ -n "$REPORTPORTAL_URL_VALUE" ]; then
        sed -i "s|PLACEHOLDER_RP_URL|$REPORTPORTAL_URL_VALUE|g" /tmp/claude-config-temp.json
    fi

    if [ -n "$REPORTPORTAL_TOKEN_VALUE" ]; then
        sed -i "s/PLACEHOLDER_RP_TOKEN/$REPORTPORTAL_TOKEN_VALUE/g" /tmp/claude-config-temp.json
    fi

    # Replace environment variables (non-sensitive)
    envsubst < /tmp/claude-config-temp.json > /root/.config/claude/config.json

    # Clear sensitive variables from memory
    unset REPORTPORTAL_URL_VALUE REPORTPORTAL_TOKEN_VALUE

    # Remove temporary file
    rm -f /tmp/claude-config-temp.json

    # Verify Claude CLI is working with Vertex AI
    echo "🧪 Testing Claude CLI with Vertex AI..."
    if ! claude --version >/dev/null 2>&1; then
        echo "❌ Claude CLI is not properly installed"
        exit 1
    fi

    # Test Vertex AI connectivity (simple status check)
    if ! claude /status >/dev/null 2>&1; then
        echo "⚠️  Warning: Could not verify Vertex AI connectivity. Proceeding anyway..."
    else
        echo "✅ Claude CLI with Vertex AI initialized successfully"
    fi
}

# Fetch the latest OSSM confidence methodology from the repository
fetch_latest_methodology() {
    echo "📥 Fetching latest OSSM confidence methodology..."

    # Set default repo URL if not provided
    local repo_url="${CI_UTILS_REPO_URL:-https://github.com/your-org/ci-utils.git}"
    local branch="${CI_UTILS_BRANCH:-main}"
    local temp_dir="/tmp/ci-utils-repo"

    # Clean up any existing temp directory
    rm -rf "$temp_dir"

    # Try to fetch the methodology file
    if git clone --depth 1 --branch "$branch" "$repo_url" "$temp_dir" >/dev/null 2>&1; then
        local methodology_file="$temp_dir/ai-helpers/ossm-release-confidence.md"

        if [ -f "$methodology_file" ]; then
            echo "✅ Successfully fetched latest methodology from $repo_url"

            # Extract the methodology content (everything after "## Technical Architecture")
            awk '/## Technical Architecture/,EOF' "$methodology_file" > /tmp/methodology-content.md

            # If that section doesn't exist, fall back to the whole file
            if [ ! -s /tmp/methodology-content.md ]; then
                cp "$methodology_file" /tmp/methodology-content.md
            fi

            echo "📄 Using latest methodology version from repository"
        else
            echo "⚠️  Methodology file not found in repository, using built-in version"
            return 1
        fi
    else
        echo "⚠️  Failed to fetch repository, using built-in methodology"
        return 1
    fi
}

# Get methodology content (either from repo or built-in)
get_methodology_content() {
    if fetch_latest_methodology; then
        cat /tmp/methodology-content.md
    else
        # Built-in fallback methodology
        cat << 'EOF'
## OSSM Release Confidence Score Methodology

### Core Factors (Weighted)

1. **Test Pass Rate (25% weight)**
   - Overall percentage of passing tests across required scope
   - Stage-specific pass rates (upstream, midstream, downstream)
   - Platform-specific pass rates
   - Threshold: >95% excellent, >85% good, <85% concerning

2. **Test Coverage Completeness (25% weight)**
   - Percentage of required test matrix actually executed
   - Platform coverage vs required platforms
   - Environment coverage vs required environments
   - Test suite coverage vs required test suites
   - Threshold: 100% required, >90% acceptable, <90% concerning

3. **Flaky Test Ratio (20% weight)**
   - Percentage of tests with inconsistent results
   - Historical flakiness patterns
   - Threshold: <5% excellent, <15% acceptable, >15% problematic

4. **Critical Defects (20% weight)**
   - Number of blocking/P0 test failures
   - Security-related failures
   - Performance regression indicators

5. **Version Stability (10% weight)**
   - Major vs minor vs patch release assessment
   - Pre-release indicators (RC, beta, alpha)
   - Component version compatibility

### Test Matrix Requirements by Scope

**FULL Scope Requirements:**
- Test Suites: O+II+KI+KU+KO+U+GIE (where applicable)
- Platforms: OSP, AWS, ROSA, ARO, IBM Z & P
- Environments: Normal, FIPS, Disconnected, IPv6, DualStack, ARM
- OCP Coverage: All compatible versions for OSSM version

**CORE Scope Requirements:**
- Test Suites: O+II+KI+KU+KO+U
- Platforms: AWS, ROSA, ARO, IBM Z & P
- Environments: Normal, FIPS, ARM
- OCP Coverage: Primary versions

**BASIC Scope Requirements:**
- Test Suites: O+II+KI+KU
- Platforms: AWS, ROSA, IBM Z & P
- Environments: Normal, FIPS
- OCP Coverage: Latest primary versions
EOF
    fi
}

# Build the confidence score prompt based on user inputs
build_prompt() {
    local build_identifier=""
    if [ -n "$BUILD_ID" ]; then
        build_identifier="Build ID: $BUILD_ID"
    else
        build_identifier="Release Candidate: $RELEASE_CANDIDATE"
    fi

    # Fetch the latest methodology content
    local methodology_content
    methodology_content=$(get_methodology_content)

    cat > /app/current-analysis-prompt.txt << EOF
Please analyze the OSSM release confidence for the following build:

$build_identifier
Change Type: $CHANGE_TYPE
OSSM Version: ${OSSM_VERSION:-auto-detect}
Target Confidence Threshold: ${CONFIDENCE_THRESHOLD:-8}
Testing Stage Focus: ${TESTING_STAGE:-all stages}

Please perform a comprehensive confidence score analysis according to the latest OSSM Release Confidence Score methodology below:

$methodology_content

Based on this methodology, analyze the following aspects:

1. **Test Scope Determination**: Validate that the testing scope ($CHANGE_TYPE) matches the nature of changes in this build
2. **Test Coverage Completeness**: Analyze coverage against required test matrix for $CHANGE_TYPE scope
3. **Test Pass Rate Analysis**: Calculate weighted pass rates across all required stages and platforms
4. **Flaky Test Assessment**: Identify and assess impact of flaky tests
5. **Critical Defect Analysis**: Review blocking/P0 failures and security issues
6. **Version Stability Assessment**: Evaluate version compatibility and stability indicators

Please provide:
- Overall confidence score (1-10)
- Test scope compliance status (MET/NOT MET)
- Detailed breakdown by platform and environment
- Missing coverage items
- Clear GO/NO-GO/SCOPE NOT MET recommendation
- Actionable next steps

Use the Report Portal MCP server to access test execution data for analysis.
EOF
}

# Run the confidence score analysis
run_analysis() {
    echo "🚀 Starting OSSM Release Confidence Score Analysis..."
    echo ""
    echo "Parameters:"
    echo "  Build/RC: ${BUILD_ID:-$RELEASE_CANDIDATE}"
    echo "  Change Type: $CHANGE_TYPE"
    echo "  OSSM Version: ${OSSM_VERSION:-auto-detect}"
    echo "  Threshold: ${CONFIDENCE_THRESHOLD:-8}"
    echo "  Stage Focus: ${TESTING_STAGE:-all stages}"
    echo "  GCP Project: $ANTHROPIC_VERTEX_PROJECT_ID"
    echo ""

    # Build the prompt
    build_prompt

    # Create reports directory if mounted
    mkdir -p /app/reports

    # Run Claude with the ossm-confidence skill
    echo "📊 Analyzing test data and calculating confidence score..."
    if claude /ossm-confidence < /app/current-analysis-prompt.txt | tee /app/reports/confidence-report.txt; then
        echo ""
        echo "✅ Analysis complete! Report saved to /app/reports/confidence-report.txt"
    else
        echo "❌ Analysis failed. Check Claude CLI configuration and Vertex AI connectivity."
        exit 1
    fi
}

# Print usage information
print_usage() {
    echo "OSSM Release Confidence Score Container (Red Hat Vertex AI)"
    echo ""
    echo "Secure Usage:"
    echo "  docker run --rm \\"
    echo "    --mount type=bind,source=./secrets/gcp-sa-key.json,target=/run/secrets/gcp_service_account_key,readonly \\"
    echo "    -e GCP_PROJECT_ID=your-team-project-id \\"
    echo "    -e BUILD_ID=OSSM-3.1.0-RC1 \\"
    echo "    -e CHANGE_TYPE=FULL \\"
    echo "    -v \$(pwd)/reports:/app/reports \\"
    echo "    ossm-confidence:latest"
    echo ""
    echo "Required:"
    echo "  - GCP service account key file (JSON format)"
    echo "  - Your team's GCP project ID from Red Hat spreadsheet"
    echo "  - BUILD_ID and CHANGE_TYPE parameters"
}

# Main execution
main() {
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        print_usage
        exit 0
    fi

    check_requirements
    setup_gcp_auth
    read_secrets
    init_claude_config
    run_analysis
}

# Run main function with all arguments
main "$@"