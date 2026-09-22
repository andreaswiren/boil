# GitLab / Forgejo / Gitea CI

Prefer workload OIDC when the CI product/version exposes trustworthy job identity claims. Otherwise use mTLS with a narrowly scoped service identity. Policy must restrict repository, project, ref, environment and signing profile rather than trusting JSON supplied by the job itself.
