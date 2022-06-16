#!/usr/bin/env sh

echo "The following environment variables are required:"
echo "    APP_COMMIT_ID The commit ID of the app to deploy"
echo "    ENVIRONMENT_ID The ID of the environment to deploy to"
echo "    APPLICATION_ID The ID of the application to deploy to"
echo "    QOVERY_API_TOKEN The Qovery API key"

set -e

# if the command did not succeed, then the job will just failed
# Doc: https://api-doc.qovery.com/#operation/deployApplication
result=$(curl -sb -X POST -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
    -d "{\"git_commit_id\": \"$APP_COMMIT_ID\"}" "https://api.qovery.com/application/$APPLICATION_ID/deploy")

echo $result

timeoutInSeconds=3600
endTime=$(($(date +%s) + timeoutInSeconds))

## wait for successful deployment
while [ "$(date +%s)" -lt $endTime ]; do
    # check deployment status
    # Doc: https://api-doc.qovery.com/#operation/getProjectEnvironmentStatus
    current_state=$(curl -sb -X GET -H 'Content-type: application/json' -H "Authorization: Token $QOVERY_API_TOKEN" \
      "https://api.qovery.com/environment/$ENVIRONMENT_ID/status" | jq -r .state)

    if [ "RUNNING" = "$current_state" ]; then
      break
    fi

    # shellcheck disable=SC2039
    if [[ "$current_state" =~ ^"ERROR_.*" ]]; then
      echo "deployment error with current state: $(current_state) - connect to https://console.qovery.com" > /dev/stderr
      exit 1
    fi

    printf "environment state: $current_state\n"

    sleep 5 # wait to check again
done

## keep going
exit 0
