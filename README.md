# konflux-component-onboarding

## Workflow for rebuild-all

Check variables override in `vars/overrides_for_rebuild_all.yaml` and assuming you are good with them, you can continue:

Create empty GitHub repos:

```
ansible-playbook playbooks/create-github-repositories.yaml -e @vars/overrides_for_rebuild_all.yaml
```

Create Konflux manifests (Applications, Components):

```
ansible-playbook playbooks/create-kflux-resource-manifests.yaml -e @vars/overrides_for_rebuild_all.yaml
```

Push template git repo to these repos:

```
ansible-playbook playbooks/push-to-github-repositories.yaml -e @vars/overrides_for_rebuild_all.yaml
```

Onboard the components to Konflux:

```
for d in rok/tenants/test-rhtap-*-tenant/jhutar-app/; do
    n="$( echo "$d" | cut -d "/" -f 3 )"
    echo "# $n"
    oc apply -k "$d"
    oc -n "$n" secrets link --for=mount loadtest-serviceaccount rhtap-perf-test-oci-storage-robot-jhutar-pull-secret
done
```

Create PR with on-pull pipeline to trigger build:

```
ansible-playbook playbooks/create-trigger-build-pipeline.yaml -e @vars/overrides_for_rebuild_all.yaml
```

Collect basic stats about the runs:

```
./check-konflux-prs.sh 1 100
```

## Linting and formatting

### yamllint

Run yamllint to check all YAML files:

    yamllint .

Configuration is in `.yamllint.yml`.

### Remove trailing whitespace

Remove trailing whitespace from all YAML files:

    find . -name '*.yml' -o -name '*.yaml' | grep -v '.git/' | xargs sed -i 's/[[:space:]]*$//'
