# RoK - RHEL on Konflux Performance Testing

This directory and its subdirectories contains configuration files intended for use with the Kustomize tool to generate Kubernetes manifests for creating namespaces/tenants in the Konflux cluster.

It includes tenant configurations ranging from test-rhtap-301-tenant through test-rhtap-3000-tenant, supporting our initial goal of creating and testing with 3,000 tenants.

The first 300 tenants are created and managed through konflux-release-data via GitOps. We tried to apply the same GitOps workflow for the remaining tenants but however, due to resource limitations on the GitLab Runner, we were suggested to take this manual creation approach instead. We were also informed that creating tenants outside of GitOps is acceptable for testing purposes.

```sh
# To create tenants/namespaces
for item in {301..301}
    do
        oc kustomize tenants/test-rhtap-$item-tenant/ | oc create -f - --dry-run=client
        echo -e '---\n'
    done
```

```sh
# To delete tenants/namespaces
for item in {301..301}
    do
        oc kustomize tenants/test-rhtap-$item-tenant/ | oc delete -f - --dry-run=client
        echo -e '---\n'
    done
```