# OSSM Release Confidence Score Container

A containerized version of the OSSM Release Confidence Score calculator using Claude Code CLI with Red Hat Vertex AI authentication.

## Quick Start

### Build the Image

```bash
docker build -t ossm-confidence:latest .
```

### Tag for Quay.io

```bash
docker tag ossm-confidence:latest quay.io/your-org/ossm-confidence:latest
```

### Push to Quay.io

```bash
docker push quay.io/your-org/ossm-confidence:latest
```

## Authentication Setup

This container uses **Red Hat's Vertex AI setup** instead of direct Claude API keys. You need:

1. **GCP Service Account Key**: JSON file with access to your team's Vertex AI project
2. **GCP Project ID**: From the Red Hat spreadsheet (same one you use for Claude Code setup)

## Usage

### Secure Usage (Recommended - Using Secret Files)

```bash
# Create GCP service account key secret file
mkdir -p secrets
cp /path/to/your-gcp-service-account.json secrets/gcp-sa-key.json
chmod 600 secrets/gcp-sa-key.json

# Run with secret file mount
docker run --rm \
  --mount type=bind,source="$(pwd)/secrets/gcp-sa-key.json",target=/run/secrets/gcp_service_account_key,readonly \
  -e GCP_PROJECT_ID="your-team-project-id" \
  -e BUILD_ID="OSSM-3.1.0-RC1" \
  -e CHANGE_TYPE="FULL" \
  -v $(pwd)/reports:/app/reports \
  quay.io/your-org/ossm-confidence:latest
```

### Alternative Usage (Environment Variable - Less Secure)

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$(pwd)/secrets/gcp-sa-key.json"
docker run --rm \
  -e GOOGLE_APPLICATION_CREDENTIALS="$GOOGLE_APPLICATION_CREDENTIALS" \
  -e GCP_PROJECT_ID="your-team-project-id" \
  -e BUILD_ID="OSSM-3.1.0-RC1" \
  -e CHANGE_TYPE="FULL" \
  -v $(pwd)/reports:/app/reports \
  quay.io/your-org/ossm-confidence:latest
```

## Required Parameters

| Parameter | Method | Description | Example |
|-----------|--------|-------------|---------|
| **GCP Service Account Key** | Secret file (recommended) | Mount at `/run/secrets/gcp_service_account_key` | `gcp-sa-key.json` |
| **GCP Service Account Key** | Environment variable | `GOOGLE_APPLICATION_CREDENTIALS` (less secure) | `./secrets/gcp-sa-key.json` |
| `GCP_PROJECT_ID` | Environment variable | Your team's GCP project ID | `ossm-team-project-123` |
| `BUILD_ID` | Environment variable | Build ID to analyze | `OSSM-3.1.0-RC1` |
| `CHANGE_TYPE` | Environment variable | Type of changes (FULL/CORE/BASIC) | `FULL` |

## Optional Parameters

| Parameter | Method | Description | Default |
|-----------|--------|-------------|---------|
| `RELEASE_CANDIDATE` | Environment variable | Alternative to BUILD_ID | - |
| `OSSM_VERSION` | Environment variable | OSSM version being tested | auto-detect |
| `CONFIDENCE_THRESHOLD` | Environment variable | Target confidence threshold | `8` |
| `TESTING_STAGE` | Environment variable | Stage focus (upstream/midstream/downstream) | all stages |
| **Report Portal URL** | Secret file (recommended) | Mount at `/run/secrets/reportportal_url` | - |
| **Report Portal Token** | Secret file (recommended) | Mount at `/run/secrets/reportportal_token` | - |
| `REPORTPORTAL_URL` | Environment variable | Report Portal URL (less secure) | - |
| `REPORTPORTAL_TOKEN` | Environment variable | Report Portal token (less secure) | - |
| `REPORTPORTAL_PROJECT` | Environment variable | Report Portal project | `osssm_general` |
| `CI_UTILS_REPO_URL` | Environment variable | Repository URL for latest prompts | `https://github.com/your-org/ci-utils.git` |
| `CI_UTILS_BRANCH` | Environment variable | Repository branch to fetch from | `main` |

## Finding Your GCP Project ID

Your GCP Project ID is the same one you used when setting up Claude Code CLI. You can find it:

1. Check your `~/.bashrc` or `~/.zshrc` for `ANTHROPIC_VERTEX_PROJECT_ID`
2. Look at the Red Hat spreadsheet mentioned in the Claude setup guide
3. Run `gcloud config get-value project` if you have gcloud configured

## Test Scope Types

- **FULL**: New minor OSSM versions (3.1, 3.2, etc.) - requires complete test matrix
- **CORE**: Code changes, CVE fixes, Istio updates - requires core test coverage
- **BASIC**: Auto base image updates - requires minimal test coverage

## Dynamic Prompt Updates

📥 **Always Up-to-Date Methodology:**
- Fetches the latest OSSM confidence methodology from this repository at runtime
- No need to rebuild the container when methodology changes
- Falls back to built-in methodology if repository is unavailable
- Configurable repository URL and branch

The container automatically pulls the latest content from `ai-helpers/ossm-release-confidence.md` to ensure the analysis uses the most current methodology and requirements.

## Security Features

🔒 **GCP Service Account Key Protection:**
- No service account keys exposed in Docker environment variables
- No keys printed to logs or console output
- Automatic cleanup of temporary files containing secrets
- Support for Docker secrets and secret file mounting

## CI/CD Integration Examples

### Jenkins Pipeline (Secure)

```groovy
pipeline {
  stages {
    stage('OSSM Confidence Analysis') {
      steps {
        // Use Jenkins GCP service account credentials
        withCredentials([file(credentialsId: 'gcp-service-account', variable: 'GCP_SA_KEY')]) {
          sh '''
            mkdir -p secrets
            cp "$GCP_SA_KEY" secrets/gcp-sa-key.json
            chmod 600 secrets/gcp-sa-key.json

            docker run --rm \
              --mount type=bind,source="$(pwd)/secrets/gcp-sa-key.json",target=/run/secrets/gcp_service_account_key,readonly \
              -e GCP_PROJECT_ID="$GCP_PROJECT_ID" \
              -e BUILD_ID="$BUILD_ID" \
              -e CHANGE_TYPE="$CHANGE_TYPE" \
              -e OSSM_VERSION="$OSSM_VERSION" \
              -e CI_UTILS_REPO_URL="https://github.com/your-org/ci-utils.git" \
              -e CI_UTILS_BRANCH="main" \
              -v $(pwd)/reports:/app/reports \
              quay.io/your-org/ossm-confidence:latest

            # Cleanup secret file
            rm -f secrets/gcp-sa-key.json
          '''
        }
        // Archive the confidence report
        archiveArtifacts artifacts: 'reports/confidence-report.txt'
      }
    }
  }
}
```

### GitLab CI (Secure)

```yaml
ossm_confidence_analysis:
  stage: test
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
  services:
    - docker:dind
  before_script:
    # Create secret file from GitLab CI variable (base64 encoded)
    - mkdir -p secrets
    - echo "$GCP_SERVICE_ACCOUNT_KEY" | base64 -d > secrets/gcp-sa-key.json
    - chmod 600 secrets/gcp-sa-key.json
  script:
    - docker run --rm
        --mount type=bind,source="$(pwd)/secrets/gcp-sa-key.json",target=/run/secrets/gcp_service_account_key,readonly
        -e GCP_PROJECT_ID="$GCP_PROJECT_ID"
        -e BUILD_ID="$BUILD_ID"
        -e CHANGE_TYPE="$CHANGE_TYPE"
        -e OSSM_VERSION="$OSSM_VERSION"
        -e CI_UTILS_REPO_URL="$CI_UTILS_REPO_URL"
        -e CI_UTILS_BRANCH="$CI_UTILS_BRANCH"
        -v $(pwd)/reports:/app/reports
        quay.io/your-org/ossm-confidence:latest
  after_script:
    # Cleanup secret file
    - rm -f secrets/gcp-sa-key.json
  artifacts:
    reports:
      junit: reports/confidence-report.txt
    paths:
      - reports/
```

## Output

The container will:
1. Analyze test data from Report Portal
2. Calculate confidence score (1-10)
3. Provide GO/NO-GO/SCOPE NOT MET recommendation
4. Output detailed analysis to CLI
5. Save report to `/app/reports/confidence-report.txt` (if volume mounted)

## Related Documentation

- [OSSM Release Confidence Score Specification](../ai-helpers/ossm-release-confidence.md)
- [Jira Epic OSSM-11131](https://issues.redhat.com/browse/OSSM-11131)