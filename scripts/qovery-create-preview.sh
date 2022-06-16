#!/usr/bin/env sh

echo "The following environment variables are required:"
echo "    PROJECT_ID The ID of the project to deploy to"
echo "    BASE_ENVIRONMENT The name of the base environment to deploy to"
echo "    QOVERY_API_TOKEN The Qovery API key"

set -e

baseEnvironmentId=$(curl -sb -X GET -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
    "https://api.qovery.com/project/$PROJECT_ID/environment" | jq -r ".results[] | select(.name==\"$BASE_ENVIRONMENT\") | .id")

# clone the environment base on the correct right branch
newEnvironmentId=$(curl -sb -X POST -d "{\"name\": \"[PR] $BRANCH_NAME\"}" -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
    "https://api.qovery.com/environment/$baseEnvironmentId/clone" | jq -r ".id")

# get all apps from env
apps=$(curl -sb -X GET -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
         "https://api.qovery.com/environment/$newEnvironmentId/application" | jq -r ".")

echo "$apps" | jq -c '.results[]' | while read row; do
    # get complete app JSON and clear necessary fields, otherwise the Qovery API returns 4xx
    app=$(echo "$row" | jq -r ".git_repository.branch=\"$BRANCH_NAME\"" | jq -r "del(.environment)" | jq -r "del(.created_at)" \
        | jq -r "del(.id)" | jq -r "del(.updated_at)" | jq -r "del(.git_repository.url)" \
        | jq -r "del(.git_repository.deployed_commit_id)" | jq -r "del(.git_repository.deployed_commit_date)" \
        | jq -r "del(.git_repository.deployed_commit_contributor)" | jq -r "del(.git_repository.deployed_commit_tag)" \
        | jq -r "del(.git_repository.provider)" | jq -r "del(.git_repository.owner)" | jq -r "del(.git_repository.has_access)" \
        | jq -r "del(.git_repository.name)" | jq -r "del(.maximum_cpu)" | jq -r "del(.maximum_memory)" | jq -r "del(.ports[].name)" \
        | jq -r "del(.storage)" | jq -r "del(.git_repository.root_path)")

    appId=$(echo "$app" | jq -r '.id')

    # escape double quotes
    formatApp=$(echo "$app" | jq -c '.' | sed 's/"/\\"/g')

    # update app via Qovery API
    savedApp=$(curl -sb -X PUT -d "$formatApp" -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
             "https://api.qovery.com/application/$appId" | jq -r '.')
done

# deploy env
result=$(curl -sb -X POST -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
    "https://api.qovery.com/environment/$newEnvironmentId/deploy")

timeoutInSeconds=3600
endTime=$(($(date +%s) + timeoutInSeconds))

## wait for successful deployment
while [ "$(date +%s)" -lt $endTime ]; do
    # check deployment status
    # Doc: https://api-doc.qovery.com/#operation/getProjectEnvironmentStatus
    current_state=$(curl -sb -X GET -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
      "https://api.qovery.com/environment/$newEnvironmentId/status" | jq -r .state)

    if [ "RUNNING" = "$current_state" ]; then
      break
    fi

    # shellcheck disable=SC2039
    if [[ "$current_state" =~ ^".*_ERROR" ]]; then
      echo "deployment error with current state: $(current_state) - connect to https://console.qovery.com" > /dev/stderr
      exit 1
    fi

    printf "environment state: $current_state\n"

    sleep 5 # wait to check again
done

## keep going
exit 0