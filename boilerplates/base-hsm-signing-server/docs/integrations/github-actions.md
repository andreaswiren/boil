# GitHub Actions integration

Use GitHub OIDC (`id-token: write`) and exchange the workflow identity with SignZone. Configure SignZone policy to validate issuer, audience, repository, workflow/ref/environment claims. The coding/build job must not hold a reusable production signing secret.

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: actions/checkout@v4
  - run: ./build.sh
  - name: Request SignZone signing
    run: ./scripts/ci/signzone-submit.sh dist/app.exe production-authenticode
```
