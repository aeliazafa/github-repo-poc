# Connecting the existing Jenkins (real setup, not part of the PoC demo)

The PoC mocks Jenkins with a workflow step. In the company, Jenkins keeps doing the deployment and
GitHub only changes what triggers it. Confirm plugin names and options with your Jenkins admin,
because they differ by version.

## What Jenkins must do

| Event on GitHub | Jenkins should |
| --- | --- |
| Push to `dev`, `sit` or `uat` | Build and deploy that environment (this is what it already does) |
| Push of tag `vX.Y.Z-rc.N` | Build that exact tag and deploy to alpha |
| Push of tag `vX.Y.Z` | Build that exact tag and deploy to prod, after a manual approval step |

## Setup outline

1. Use a Multibranch Pipeline job with the GitHub Branch Source plugin.
2. Under Behaviours, keep "Discover branches" filtered to `dev|sit|uat|main`, and add "Discover tags".
3. In the GitHub repository add a webhook to your Jenkins URL (for the GitHub plugin this is
   `https://<jenkins>/github-webhook/`). Send push events. Check that tag pushes also reach Jenkins;
   if they do not, use a multibranch scan webhook trigger plugin or a periodic scan as a fallback.
4. Jenkins must be reachable from GitHub. If it sits on an internal network, ask IT for a reachable
   webhook endpoint or a self-hosted runner that calls Jenkins instead.
5. Store Jenkins credentials in GitHub or Jenkins credentials, never in the repository.

## Example Jenkinsfile

```groovy
pipeline {
  agent any
  stages {
    stage('Build') {
      steps { sh 'echo build' }
    }
    stage('Deploy dev')  { when { branch 'dev' }  steps { sh './deploy.sh dev' } }
    stage('Deploy sit')  { when { branch 'sit' }  steps { sh './deploy.sh sit' } }
    stage('Deploy uat')  { when { branch 'uat' }  steps { sh './deploy.sh uat' } }
    stage('Deploy alpha') {
      when { tag pattern: 'v\\d+\\.\\d+\\.\\d+-rc\\.\\d+', comparator: 'REGEXP' }
      steps { sh './deploy.sh alpha' }
    }
    stage('Deploy prod') {
      when { tag pattern: '^v\\d+\\.\\d+\\.\\d+$', comparator: 'REGEXP' }
      steps {
        input message: 'Deploy this tag to prod?'
        sh './deploy.sh prod'
      }
    }
  }
}
```

## Why deploy from a tag

A tag points at one exact commit and is not supposed to move. Alpha and prod therefore run exactly
what was tested, and rolling back means redeploying an earlier tag.

## Reporting the regression result to GitHub

The final (prod) tag is accepted only when the tip of the release branch has a commit status named
`regression` with state `success` (or the tag is a recorded `SKIP-REGRESSION:` waiver).

| Who | How the status gets there |
| --- | --- |
| Jenkins, automated suite | After deploying the rc tag to alpha, Jenkins runs the automation job (the other team's repository script) and posts the result with the GitHub commit status API, context `regression`, `target_url` pointing at the Jenkins report. Use a service account whose token can only write commit statuses on this repository. |
| QA, manual regression | Actions tab, "Record regression result", fill in branch, result, mode and an evidence link. The job waits for approval in the `qa-signoff` environment. |

Example Jenkins step (run on the commit being tested; keep the token in Jenkins credentials):

```groovy
post {
  always {
    sh """
      curl -fsS -X POST -H "Authorization: Bearer $GH_STATUS_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/OWNER/REPO/statuses/$GIT_COMMIT \
        -d '{"state":"${currentBuild.currentResult == 'SUCCESS' ? 'success' : 'failure'}","context":"regression","target_url":"$BUILD_URL","description":"Automation suite"}'
    """
  }
}
```

How Jenkins starts the automation script is decided later; this status is the only contract the
pipeline needs. A new commit on the release branch has no status, so it must be tested again.


boss proposal: https://claude.ai/artifact/JggWBcKYrFoaJox889Wsq4#9470dae2-d767
setup guide: https://claude.ai/artifact/CfXofe1DLfsR5QNEWhtfxK#017b5d82-bdf4

