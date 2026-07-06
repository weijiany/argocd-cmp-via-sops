# argocd-cmp-via-sops

An [Argo CD Config Management Plugin](https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/)
sidecar image that renders Helm charts with [SOPS](https://github.com/getsops/sops)-encrypted
value files via the [`helm-secrets`](https://github.com/jkroepke/helm-secrets) plugin.

The plugin supports two chart-source patterns:

- **Chart in a Helm registry** — pulled at render time with basic-auth credentials.
- **Chart in the git repo** — rendered in place after `helm dependency build`.

Discovery is triggered by the presence of a `.sops.yaml` file in the application source.

## Repository layout

| Path                              | Purpose                                                                                                                    |
|-----------------------------------|----------------------------------------------------------------------------------------------------------------------------|
| `Dockerfile`                      | CMP sidecar image: alpine + `sops` + `helm` + `git` + `helm-secrets` plugin.                                               |
| `helmfile.yaml`                   | Installs the upstream `argo/argo-cd` chart with the plugin wired in.                                                       |
| `values/argocd.yaml`              | Argo CD values: registers the CMP under `configs.cmp.plugins` and attaches the sidecar under `repoServer.extraContainers`. |
| `examples/chart-in-registry.yaml` | `ApplicationSet` example for a chart pulled from a Helm registry.                                                          |
| `examples/chart-in-repo.yaml`     | `ApplicationSet` example for a chart living inside the git repo.                                                           |

## Build

```sh
docker build -t argo-cmp .
```

The image runs as UID `999` to match the Argo CD repo-server user, and installs
`helm-secrets` under `HELM_PLUGINS=/helm-plugins`.

## Install

```sh
helmfile apply
```

This deploys Argo CD with:

- `configs.cmp.plugins.helm-secrets` — the plugin generate/discover contract.
- `repoServer.extraContainers[helm-secrets]` — the sidecar that runs the plugin.

The sidecar mounts the shared `var-files` and `plugins` volumes provided by Argo CD's
`copyutil` init container, plus an `emptyDir` at `/tmp` for scratch space.

The sidecar reads AWS credentials from the `aws-jenkins-user-credential` secret
(`envFrom`) so SOPS can decrypt KMS-backed files. Adjust the secret name / auth
mechanism to match your KMS provider before deploying.

## Using the plugin

Reference the plugin from an `Application` / `ApplicationSet` under `spec.source.plugin`:

```yaml
plugin:
  name: helm-secrets
  env:
    - name: VALUES_PATHS
      value: path/to/values.yaml,path/to/overrides.yaml
    - name: SECRET_PATHS
      value: path/to/secrets.yaml
    # Either CHART_PATH (chart in git) …
    - name: CHART_PATH
      value: charts/my-app
    # … or CHART_REGISTRY_URL + CHART_NAME + CHART_VERSION (chart in registry)
    - name: CHART_REGISTRY_URL
      value: https://helm.example.com
    - name: CHART_NAME
      value: my-app
    - name: CHART_VERSION
      value: "1.2.3"
```

### Environment contract

| Variable                                        | Required      | Meaning                                                                                                                                            |
|-------------------------------------------------|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| `VALUES_PATHS`                                  | yes           | Comma-separated Helm value files. Missing paths are silently skipped, which lets you list optional per-env overrides.                              |
| `SECRET_PATHS`                                  | yes           | Comma-separated SOPS-encrypted value files, resolved through `secrets://`. Missing paths are silently skipped.                                     |
| `CHART_PATH`                                    | one of        | Path to a chart inside the app's git source. `helm dependency build` runs before templating.                                                       |
| `CHART_REGISTRY_URL`                            | one of        | Helm registry URL. When set together with `CHART_NAME` and `CHART_VERSION`, the chart is pulled and untarred into a temp `HOME` before templating. |
| `CHART_NAME`                                    | with registry | Chart name in the registry.                                                                                                                        |
| `CHART_VERSION`                                 | with registry | Selects the registry-pull code path. Presence of this variable is what switches modes.                                                             |
| `GITLAB_ARGO_USERNAME` / `GITLAB_ARGO_PASSWORD` | with registry | Basic-auth credentials used by `helm pull`. Provide via a Kubernetes secret on the sidecar — do not hardcode.                                      |

`ARGOCD_APP_NAME` and `ARGOCD_APP_NAMESPACE` are injected by Argo CD and used as
the Helm release name and target namespace.

### Discovery

The plugin's `discover.fileName` is `./.sops.yaml`. Any application source that
ships a `.sops.yaml` at its root will be matched to this plugin automatically —
no `plugin.name` override needed if you prefer discovery-based routing.

## Examples

See [`examples/`](./examples/) for complete `ApplicationSet` manifests covering
both chart-source patterns.
