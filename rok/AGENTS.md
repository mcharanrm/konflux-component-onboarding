# RoK Scenario Instructions for AI Agents

Instructions for AI agents working on RHEL on Konflux (RoK) performance testing tasks.

## Overview
RoK tests Konflux scalability (3,000+ tenants). Two main workflows exist in the `rok/` directory.

## Workflows

### 1. Rebuild-all (Container)
- **Goal**: Simulate high-volume container builds.
- **Location**: `rok/tenants/test-rhtap-N-tenant/app/`
- **Key Files**: `kustomization.yaml` (patches `Application`, `Component`, `ReleasePlan`, `ITS`).
- **Convention**: Uses standard names like `app` and `comp` in base, patched to `app` and `comp` (or specific names if requested).
- **Automation**: Managed via `playbooks/` and `rok/create-tenant-config-playbook.yaml`.

### 2. Package Workflow (RPM)
- **Goal**: Test concurrent RPM builds.
- **Location**: `rok/tenants/test-rhtap-N-tenant/example-packages/`
- **Key Files**: `kustomization.yaml`, `konflux-perf-scale-release-plan.yaml`.
- **Convention**: Points to package-specific Git repos (e.g., `mcharanrm/example-rok-...`).

## Tooling & Commands

### Kustomize
Always use `oc kustomize` to verify manifest generation before applying.
```bash
oc kustomize rok/tenants/test-rhtap-1-tenant/app/
```

### Applying to Cluster
Use `oc apply -k`. Often done in loops for scale testing.
```bash
# Apply rebuild-all for a range
for i in {1..100}; do
    oc apply -k rok/tenants/test-rhtap-$i-tenant/app/
done
```

### Ansible
Use `rok/create-tenant-config-playbook.yaml` to generate new tenant configs.
Parameters: `starts_from`, `ends_at`.

## Context Links
- Global Context: [../CONTEXT.md](../CONTEXT.md)
- Jira (Rebuild-all): KONFLUX-12492
- Jira (RPM): KONFLUX-8167
