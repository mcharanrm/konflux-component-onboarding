# konflux-component-onboarding

## What is this project?

This project automates the process of **onboarding large numbers of software components into [Konflux](https://konflux-ci.dev/)** — Red Hat's cloud-native CI/CD platform — so that performance and scalability testing can be carried out at scale.

In simple terms: instead of manually setting up hundreds or thousands of test projects in Konflux one-by-one (creating namespaces, GitHub repositories, build pipelines, release plans, etc.), this tooling does it all automatically with a single command.

---

## Why does this exist?

Testing how Konflux behaves under real-world load requires spinning up many tenants (isolated workspaces) simultaneously. Doing this by hand would take days and be error-prone. This repo provides the **infrastructure-as-code** (Ansible playbooks + Kustomize manifests) to do it in minutes.

It currently supports two test scenarios:

| Scenario | Name | Description |
|----------|------|-------------|
| **RoK** | RHEL on Konflux | Tests Konflux handling RPM-based RHEL packages at scale (up to ~3,000 tenants) |
| **FKX** | Fedora on Konflux | Similar workload for Fedora packages |

---

## How does it work? (Big Picture)

```
Configure → Preflight Checks → Generate Names → Run Playbooks → Apply to Cluster
```

1. **Configure** — You edit a single config file (`vars/konflux_repo_app_component_config.yml`) to set the tenant range, naming prefixes, and which test scenario to run.
2. **Preflight checks** — The tooling validates your inputs before doing anything.
3. **Name generation** — It automatically generates consistent, numbered names for every GitHub repo, Konflux application, component, and tenant namespace that needs to be created.
4. **Playbooks** — You run whichever Ansible playbooks you need:
   - Create GitHub repositories and register them with the Konflux GitHub App
   - Generate Konflux `Application` and `Component` Kubernetes manifests for each tenant
   - Clone an RPM source repository, push it to each generated fork, and open a Pull Request that adds a CI pipeline
   - Add collaborators or accept invitations in bulk
5. **Apply to cluster** — Use `oc kustomize | oc create` to apply all the generated manifests to an OpenShift cluster.

---

## Prerequisites

- **Ansible** (with Jinja2 native mode)
- **`oc`** (OpenShift CLI) or **`kubectl`**
- A GitHub **Personal Access Token** (PAT) stored at `~/.github-pat.json`
- Access to a Konflux staging environment
- Familiarity with Kustomize

---

## Repository Layout

```
konflux-component-onboarding/
├── vars/
│   └── konflux_repo_app_component_config.yml   # ← Main config file. Edit this first.
├── playbooks/                                   # Ansible playbooks (entry points)
│   ├── create-github-repositories.yaml         # Create GitHub repos + attach to Konflux App
│   ├── delete-github-repositories.yaml         # Tear down repos
│   ├── create-kflux-resource-manifests.yaml    # Generate Konflux App/Component manifests
│   ├── create-trigger-build-pipeline.yaml      # Open RPM PAC pipeline PRs
│   ├── add-repository-collaborator.yaml        # Add admin collaborators
│   └── accept-repository-invitations.yaml      # Bulk-accept GitHub invitations
├── preflight-checks/                            # Input validation tasks
├── generate-resource-names/                     # Deterministic name generation tasks
├── create-repositories/                         # GitHub API tasks
├── delete-repositories/                         # GitHub API tasks
├── create-konflux-manifests/                    # Kustomize base + manifest generation tasks
├── create-build-pipelines/                      # RPM build pipeline PR tasks
├── rok/                                         # RoK-specific resources
│   ├── README.md                                # Operational notes for RoK
│   ├── base/                                    # Shared namespace/RBAC/quota base
│   ├── quota/                                   # ResourceQuota + LimitRange definitions
│   ├── templates/                               # Jinja2 templates for tenant overlays
│   ├── create-tenant-config-playbook.yaml       # Generate per-tenant kustomization files
│   └── tenants/                                 # Auto-generated per-tenant Kustomize overlays
│       └── test-rhtap-<N>-tenant/
│           └── example-packages/
└── ansible.cfg                                  # Ansible configuration
```

---

## Quick Start

### Step 1 — Configure

Edit `vars/konflux_repo_app_component_config.yml` to set your desired tenant range and test scenario:

```yaml
starts_from: 301          # First tenant number
ends_at: 400              # Last tenant number
test_scenario: rok         # 'rok' (RHEL) or 'fkx' (Fedora)
```

Ensure `~/.github-pat.json` exists with your GitHub Personal Access Token.

> **Note:** Several paths and org names in the config (e.g. `mcharanrm`, Quay org, GitHub App installation ID) are environment-specific. Update them to match your own Konflux staging environment before running.

### Step 2 — Create GitHub repositories

```bash
ansible-playbook playbooks/create-github-repositories.yaml
```

### Step 3 — Generate Konflux manifests

```bash
ansible-playbook playbooks/create-kflux-resource-manifests.yaml
```

### Step 4 — Generate per-tenant Kustomize overlays (RoK)

```bash
ansible-playbook rok/create-tenant-config-playbook.yaml -e "starts_from=301 ends_at=400"
```

### Step 5 — Apply to cluster

```bash
for i in $(seq 301 400); do
  oc kustomize rok/tenants/test-rhtap-${i}-tenant/example-packages | oc create -f -
done
```

For a dry run first:

```bash
oc kustomize rok/tenants/test-rhtap-301-tenant/example-packages | oc create --dry-run=client -f -
```

### Teardown

```bash
ansible-playbook playbooks/delete-github-repositories.yaml
```

---

## Key Concepts

| Term | What it means |
|------|--------------|
| **Tenant** | An isolated Konflux workspace (a Kubernetes namespace) for one "team" or test user |
| **Application** | A Konflux grouping of one or more software components |
| **Component** | A single buildable unit (a Git repo + Dockerfile) inside a Konflux Application |
| **ReleasePlan** | Tells Konflux where and how to release a built component |
| **PAC (Pipelines-as-Code)** | A Tekton feature that triggers CI pipeline runs directly from Pull Requests |
| **Kustomize** | A tool that customizes Kubernetes YAML files by layering "overlays" on top of a "base" |
| **RoK** | "RHEL on Konflux" — the performance test scenario using RHEL RPM packages |

---

## RoK Tenant Ranges

| Range | Managed by |
|-------|-----------|
| Tenants 1 – 300 | `konflux-release-data` GitOps repository (separate repo) |
| Tenants 301 – 3000 | This repository (manually applied with `oc kustomize`) |

See [`rok/README.md`](rok/README.md) for detailed operational notes on the RoK scenario.

---

## Contributing

When adding new tenants or modifying the base manifests:
- The `rok/tenants/` directory is auto-generated — do not edit individual tenant files by hand. Re-run the tenant config playbook instead.
- The `build-pipelines-workspace/` and `scratch-space/` directories are local working directories and are git-ignored.
