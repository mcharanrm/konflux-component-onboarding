# konflux-component-onboarding

## Linting and formatting

### yamllint

Run yamllint to check all YAML files:

    yamllint .

Configuration is in `.yamllint.yml`.

### Remove trailing whitespace

Remove trailing whitespace from all YAML files:

    find . -name '*.yml' -o -name '*.yaml' | grep -v '.git/' | xargs sed -i 's/[[:space:]]*$//'
