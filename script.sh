################ SET RUN TYPE DEUBGING ################
# RUN_TYPE="installation" #debugging                  #
# RUN_TYPE="nightly" #debugging                       #
#######################################################

max_attempts=60
sleep_interval=5

check_thanos_querier_status() {
  local attempts=0

  while [[ $attempts -lt $max_attempts ]]; do
    route_exists=$(oc get route thanos-querier -n openshift-monitoring --ignore-not-found=true)
    if [[ -n $route_exists ]]; then
      echo "route \"thanos-querier\" is up and running in namespace "openshift-monitoring"."
      return 0
    else
      echo "Thanos Querier route is not up yet. Retrying in $sleep_interval seconds..."
    fi
    sleep $sleep_interval
    attempts=$((attempts + 1))
  done

  echo "Timed out. Thanos Querier route did not spin up in the \"openshift-monitoring\" namespace."
  return 1
}

check_user_workload_monitoring_enabled() {
  uwm_namespace_exists=$(oc get project openshift-user-workload-monitoring --ignore-not-found=true) 
  if [[ -z $uwm_namespace_exists ]]; then
    echo "Error, project \"openshift-user-workload-monitoring\" does not exist."
    exit 1
  fi
  PROM_TOKEN_SECRET_NAME=$(oc get secret -n openshift-user-workload-monitoring | grep  prometheus-user-workload-token | head -n 1 | awk '{print $1 }')
  if [[ -z $PROM_TOKEN_SECRET_NAME ]]; then 
    echo "Error, could not find a secret for the \"prometheus-user-workload-token\" in namespace \"openshift-user-workload-monitoring\"."
    exit 1
  fi
  PROM_TOKEN_SECRET_TOKEN=$(oc get secret $PROM_TOKEN_SECRET_NAME -n openshift-user-workload-monitoring -o json | jq -r '.data.token')
  if [[ -z $PROM_TOKEN_SECRET_TOKEN || $PROM_TOKEN_SECRET_TOKEN == "null" ]]; then
    echo "Error, could not get token data for the secret for the \"prometheus-user-workload-token\" in namespace \"openshift-user-workload-monitoring\"."
    exit 1
  fi
  exit 0
}

check_pull_secret_exists() {
  local attempts=0

  while [[ $attempts -lt $max_attempts ]]; do
    pull_secret_exists=$(oc get secret pull-secret -n trusted-artifact-signer-monitoring --ignore-not-found=true)
    if [[ -n $pull_secret_exists ]]; then
      echo "secret \"pull-secret\" in namespace \"trusted-artifact-signer-monitoring\" exists, proceeding."
      return 0
    else
      echo "Waiting for secret \"pull-secret\" in namespace \"trusted-artifact-signer-monitoring\" to exist..."
      sleep $sleep_interval
      attempts=$((attempts + 1))
    fi
  done

  echo "Timed out. Cannot find secret \"pull-secret\" in namespace \"trusted-artifact-signer-monitoring\"."
  echo "Please download the pull-secret from \`https://console.redhat.com/application-services/trusted-content/artifact-signer\`
  and create a secret from it: \`oc create secret generic pull-secret -n trusted-artifact-signer-monitoring --from-file=\$HOME/Downloads/pull-secret.json\`."
  return 1
}

check_pull_secret_data() {
  pull_secret=$(oc get secret pull-secret -n trusted-artifact-signer-monitoring --ignore-not-found=true -o json)
  if [[ -n $pull_secret ]]; then
    pull_secret_userID=$(echo $pull_secret | jq '.data."pull-secret.json"')
    if [[ $pull_secret_userID == "null" ]]; then
      echo "error parsing secret \"pull-secret\" in namespace \"trusted-artifact-signer-monitoring\"": did not have property \`.data.pull-secret.json\`.
      exit 1
    fi
    exit 0
  else
    echo "No TAS pull-secret found. If you would like to send metrics or recieve support support,
      please download the pull-secret from \`https://console.redhat.com/application-services/trusted-content/artifact-signer\`.
      Then create the secret \"pull-secret\" in namespace \"trusted-artifact-signer-monitoring\" from the value:  \`oc create secret generic pull-secret -n trusted-artifact-signer-monitoring --from-file=\$HOME/Downloads/pull-secret.json\`
      "
    exit 1
  fi
}



pse=$(check_pull_secret_exists)
psd=$(check_pull_secret_data)
console_route=$(oc get route console -n openshift-console | grep "console-openshift-console" | awk '{print $2}')
base_domain=${console_route:31:((${#console_route}-31))}

if [[ "$pse" == "1" || "$psd" == "1" ]]; then
  org_id="41414141"
  user_id="41414141"
else 
  secret_data=$(oc get secret pull-secret -n trusted-artifact-signer-monitoring -o "jsonpath={.data.pull-secret\.json}")
  org_id=$(echo $secret_data | base64 -d | jq ".orgId" | cut -d "\"" -f 2 )
  user_id=$(echo $secret_data | base64 -d  | jq ".userId" | cut -d "\"" -f 2 )
fi

jq -n '{"org_id": $ARGS.named["org_id"],"user_id": $ARGS.named["user_id"], "cluster": $ARGS.named["cluster"]}' \
  --arg org_id $org_id \
  --arg user_id $user_id \
  --arg cluster $base_domain > /opt/app-root/src/tmp

if [[ $RUN_TYPE == "nightly" ]]; then
  check_user_workload_monitoring_enabled
  check_thanos_querier_status

  
  PROM_TOKEN_SECRET_NAME=$(oc get secret -n openshift-user-workload-monitoring | grep  prometheus-user-workload-token | head -n 1 | awk '{print $1 }')
  PROM_TOKEN_DATA=$(echo $(oc get secret $PROM_TOKEN_SECRET_NAME -n openshift-user-workload-monitoring -o json | jq -r '.data.token') | base64 -d)
  THANOS_QUERIER_HOST=$(oc get route thanos-querier -n openshift-monitoring -o json | jq -r '.spec.host')

  fulcio_new_certs_query_data=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=fulcio_new_certs" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[]' )
  if [[ -z $fulcio_new_certs ]]; then 
    echo "Error with fulcio deployment, metric does not exist."
    fulcio_new_certs="null"
  else 
    fulcio_new_certs=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=fulcio_new_certs" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[] | .value[1]')
    fulcio_new_certs=$(echo $fulcio_new_certs | cut -d "\"" -f 2 )
  fi

  rekor_new_entries_query_data=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_new_entries" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[]' )
  declare rekor_new_entries
  if [[ -z $rekor_new_entries_query_data ]]; then
    echo "Error with rekor deployment, metric does not exist."
    rekor_new_entries="null"
  else 
    rekor_new_entries=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_new_entries" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[] | .value[1]')
    rekor_new_entries=$(echo $rekor_new_entries | cut -d "\"" -f 2 )
  fi

  rekor_qps_by_api_query_data=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query" --data-urlencode "query=rekor_qps_by_api" -H "Authorization: Bearer $PROM_TOKEN_DATA" | jq '.data.result[]' )
  if [[ -z $rekor_qps_by_api_query_data ]]; then
    echo "Cannot access metric \`rekor_qps_by_api\`."
    rekor_qps_by_api=("")
  else 
    rekor_qps_by_api=$(curl -X GET -kG "https://$THANOS_QUERIER_HOST/api/v1/query?" --data-urlencode "query=rekor_qps_by_api" -H "Authorization: Bearer $PROM_TOKEN_DATA" | \
    jq -r '.data.result[] | "{\"method\":\"" + .metric.method + "\",\"status_code\":" + .metric.code + ",\"path\":\"" + .metric.path + "\",\"value\":" + .value[1] + "},"')
    
  fi
    jq -i 
    # jq -n '{"org_id": $ARGS.named["org_id"],"user_id": $ARGS.named["user_id"],"fulcio_new_certs": $ARGS.named["fulcio_new_certs"],"rekor_new_entries": $ARGS.named["rekor_new_entries"], "rekor_qps_by_api": $rekor_qps_by_api}' \
    # --arg org_id $org_id \
    # --arg user_id $user_id \
    # --arg fulcio_new_certs $fulcio_new_certs \
    # --arg rekor_new_entries $rekor_new_entries \
    # --arg rekor_qps_by_api "${rekor_qps_by_api_arr[@]}" > /opt/app-root/src/tmp
fi

if [[ $RUN_TYPE == "nightly" ]]; then
  python3 /opt/app-root/src/main-nightly.py
elif [[ $RUN_TYPE == "installation" ]]; then
  python3 /opt/app-root/src/main-installation.py
else 
  echo "error \$RUN_TYPE not set.
    options: \"nightly\", \"installation\""
  exit 1
fi