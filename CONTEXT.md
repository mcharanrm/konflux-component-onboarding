# Context: RoK (RHEL on Konflux Performance Testing)

## Glossary

### RoK
RHEL on Konflux. Performance testing initiative for Konflux at scale.
Target: 3,000+ tenants, 6,000+ builds (CS/RHEL mass-rebuild simulation).

### Tenant
Kubernetes namespace. Pattern: `test-rhtap-N-tenant`.
Isolated environment for Konflux resources.

### Onboarding
Creating Konflux CRs (`Application`, `Component`, `ReleasePlan`, `IntegrationTestScenario`) in a tenant.
Triggers build/release pipelines.

### Rebuild-all Workflow
Simulation of mass-rebuild using controlled container components.
Resources: `rok/tenants/test-rhtap-N-tenant/app/` (formerly `jhutar-app`).
Jira: KONFLUX-12492.

### Package Workflow (RPM)
Testing concurrent RPM builds using real/controlled packages.
Resources: `rok/tenants/test-rhtap-N-tenant/example-packages/`.
Jira: KONFLUX-8167.

## Architecture

Layered Kustomize setup for 3,000 tenants.

### Base Resources
- `create-konflux-manifests/overlays/container`: Base for container builds.
- `create-konflux-manifests/overlays/package`: Base for RPM/package builds.

### Tenant Overlays
Located in `rok/tenants/test-rhtap-N-tenant/`.
- `app/`: Rebuild-all simulation. Injects unique Git repo, namespace.
- `example-packages/`: RPM build simulation. Injects package-specific Git repo.

## Workflows

### Manifest Generation
Playbook: `rok/create-tenant-config-playbook.yaml`.
Generates kustomize overlays for N tenants.

### Applying Manifests
First 300: GitOps (konflux-release-data).
301-3000+: Manual `oc apply -k`.
Loop example:
```bash
for d in rok/tenants/test-rhtap-*-tenant/app/; do
    oc apply -k "$d"
done
```
