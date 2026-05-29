# konflux-component-onboarding

## Workflow for rebuild-all

Check variables override in `vars/overrides_for_rebuild_all.yaml` and assuming you are good with them, you can continue:

Create empty GitHub repos:

    ansible-playbook playbooks/create-github-repositories.yaml -e @vars/overrides_for_rebuild_all.yaml

Create Konflux manifests (Applications, Components):

    ansible-playbook playbooks/create-kflux-resource-manifests.yaml -e @vars/overrides_for_rebuild_all.yaml

Push template git repo to these repos:

    ansible-playbook playbooks/push-to-github-repositories.yaml -e @vars/overrides_for_rebuild_all.yaml

Onboard the components to Konflux:

    for i in {1..100}; do
        echo "# $i"
        n="test-rhtap-$i-tenant"
        d="rok/tenants/$n/jhutar-app/"
        oc apply -k "$d"
        oc -n "$n" secrets link --for=mount loadtest-serviceaccount rhtap-perf-test-oci-storage-robot-jhutar-pull-secret
    done

Create PR with on-pull pipeline to trigger build:

    ansible-playbook playbooks/create-trigger-build-pipeline.yaml -e @vars/overrides_for_rebuild_all.yaml

Collect basic stats about the runs:

    ./check-on-pull-prs.sh 1 100

Optionally you can merge these PRs (from `konflux-example-repo-*` branch):

    for i in {1..100}; do
        echo "# $i"
        gh pr merge konflux-example-repo-$i --rebase --delete-branch --repo jhutar/example-repo-$i
    done

and trigger on-push build directly for releases to happen:

    ansible-playbook playbooks/trigger-push-build.yaml -e @vars/overrides_for_rebuild_all.yaml

## Linting and formatting

### yamllint

Run yamllint to check all YAML files:

    yamllint .

Configuration is in `.yamllint.yml`.

### Remove trailing whitespace

Remove trailing whitespace from all YAML files:

    find . -name '*.yml' -o -name '*.yaml' | grep -v '.git/' | xargs sed -i 's/[[:space:]]*$//'
