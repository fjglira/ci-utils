# DevLake Test Registry Results Sender

Pushes sail-operator E2E test results to the **DevLake Test Registry (Konflux)**
as a post-build Jenkins step, replacing the offline download + batch flow.

## Prerequisites

- `jq` — JSON processor
- `python3` — timestamp conversion
- `curl` — HTTP client
- A Jenkins credential of type **Secret text** containing the DevLake API token

## How It Works

1. Reads `ossm-env-snapshot.json` and `report.xml` from the Jenkins workspace.
2. Derives `job_name` from the snapshot (OSSM version, OCP version, arch, platform,
   network, flags) — compatible with OSSM Quality dashboard regexes.
3. Sets `job_id = "${job_name}-${BUILD_NUMBER}"` — idempotent: retrying the same
   build overwrites the same record.
4. Maps Jenkins result → `SUCCESS / FAILURE / ABORTED`.
5. POSTs timing (`startedAt`, `finishedAt`, `durationSec`) and `report.xml` to the
   Test Registry API.

## Jenkins Integration

### 1. Create the credential

In **Manage Jenkins → Credentials → System → Global credentials → Add**:

| Field | Value |
|-------|-------|
| Kind | Secret text |
| ID | `devlake-api-key` |
| Secret | DevLake Bearer token |

### 2. Add a post block to `sail-operator-e2e-tests.jenkinsfile`

```groovy
environment {
    DEVLAKE_BASE = 'https://konflux-devlake-ui-konflux-devlake.apps.rosa.kflux-c-prd-i01.7hyu.p3.openshiftapps.com'
    // DEVLAKE_CONNECTION defaults to 'ossm' in the script
}

post {
    always {
        script {
            if (fileExists('ossm-env-snapshot.json') && fileExists('report.xml')) {
                withCredentials([string(credentialsId: 'devlake-api-key', variable: 'DEVLAKE_API_KEY')]) {
                    env.BUILD_RESULT      = currentBuild.currentResult
                    env.BUILD_START_MS    = currentBuild.startTimeInMillis.toString()
                    env.BUILD_DURATION_MS = currentBuild.duration.toString()
                    sh '''
                        curl -fsSL https://raw.githubusercontent.com/openshift-service-mesh/ci-utils/main/devlake/send_testregistry_results.sh \
                          | bash
                    '''
                }
            } else {
                echo 'devlake-push: artifacts missing — skipping (early abort?)'
            }
        }
    }
}
```

> **Vendored alternative** — if outbound GitHub access is blocked on the Jenkins agent,
> copy `devlake/send_testregistry_results.sh` into the test repo and call it directly:
> ```groovy
> sh 'bash devlake/send_testregistry_results.sh'
> ```

### When the step runs

The step runs in `post { always { } }` — after every build (success, failure, unstable,
aborted). If either artifact is missing (e.g. very early abort), the step is skipped
by the `fileExists` guard in the Jenkinsfile.

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `DEVLAKE_BASE` | DevLake base URL | `https://konflux-devlake-ui-...` |
| `DEVLAKE_API_KEY` | Bearer token | injected via `withCredentials` |

### From Jenkins (pass from `currentBuild`)

| Variable | Source | Description |
|----------|--------|-------------|
| `BUILD_NUMBER` | automatic | Jenkins build number |
| `BUILD_URL` | automatic | Link to build in Jenkins UI |
| `BUILD_RESULT` | `currentBuild.currentResult` | `SUCCESS \| FAILURE \| UNSTABLE \| ABORTED` |
| `BUILD_START_MS` | `currentBuild.startTimeInMillis` | Build start epoch ms |
| `BUILD_DURATION_MS` | `currentBuild.duration` | Build duration ms |

### Optional overrides

| Variable | Default | Description |
|----------|---------|-------------|
| `DEVLAKE_CONNECTION` | `ossm` | Test Registry connection name |
| `DEVLAKE_ORG` | `OSSM` | Organization field |
| `DEVLAKE_REPO` | `downstream-ossm` | Repository field |
| `DEVLAKE_SCOPE_ID` | `sail-operator` | Scope ID field |
| `SNAPSHOT_FILE` | `ossm-env-snapshot.json` | Path to env snapshot |
| `JUNIT_FILE` | `report.xml` | Path to JUnit XML |

## Local / dry-run testing

```bash
export DEVLAKE_BASE='https://konflux-devlake-ui-...'
export DEVLAKE_API_KEY='...'
export BUILD_NUMBER='9999'
export BUILD_URL='https://jenkins.example.com/job/sail/9999/'
export BUILD_RESULT='SUCCESS'
export BUILD_START_MS='1700000000000'
export BUILD_DURATION_MS='3600000'

./devlake/send_testregistry_results.sh --dry-run --verbose
```

## Verification

**SQL** (run in Grafana Explore or directly against the lake DB):

```sql
SELECT job_id, job_name, result, started_at, finished_at, duration_sec
FROM   ci_test_jobs
WHERE  job_name LIKE 'downstream-%'
ORDER  BY finished_at DESC
LIMIT  5;
```

**Grafana:** open _OSSM Quality: Downstream Test Runs_ → set time range **Last 90 days**.
A new row appears within ~30 seconds of the build finishing.

## Notes

- `job_name` is derived from the env snapshot to stay compatible with OSSM Quality
  dashboard regexes (`release-X.Y`, `ocp-X.Y`, `-arm`, `-fips`).
- Re-running the same build is safe: the same `job_id` overwrites the existing record.
- When `extraArgs` support is deployed on DevLake, uncomment the `-F "extraArgs=@..."` line
  inside the script (it is already present as a comment).
