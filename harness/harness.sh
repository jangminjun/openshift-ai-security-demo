#!/usr/bin/env bash
# OpenShift AI security/RBAC demo harness.
#
# Unlike openshift-aws-harness (which drives a bastion over SSH), this runs oc
# locally against whatever cluster oc is logged in to -- so it survives sandbox
# rotation: point local.env at the new cluster, 'login', then re-run the preps.
# All prep/stop commands are idempotent.
#
# Usage: ./harness.sh <command>
#
#   login                 oc login using OCP_API_URL/OCP_USER/OCP_PASSWORD from local.env
#   check                 preflight: login, RHOAI version, DSC, dashboard feature flags
#   prep-all              scenario1-prep + scenario2-prep + scenario3-prep
#   stop-all              scenario1-stop + scenario2-stop + scenario3-stop
#   destroy-project       delete the demo project (and everything in it)
#
#   scenario1-prep        demo project for the custom RBAC role UI demo
#   scenario1-bind        bind the custom roles to the demo users (creates a role from manifests/ if the UI step was skipped)
#   scenario1-verify      print what each demo user may and may not do in the project
#   scenario1-stop        delete the custom Roles and their RoleBindings
#
#   The demo users' login accounts (wb-maintainer / wb-reader / wb-none) are
#   NOT created here -- add them to the cluster's identity provider yourself.
#
#   scenario2-prep        demo project + a pre-existing Secret (stands in for External Secrets/Vault)
#   scenario2-verify      show the workbench references the Secret instead of copying values
#   scenario2-stop        delete the workbench and the Secret
#
#   scenario3-prep        confirm the DSC oauthProxy field exists, show the before state
#   scenario3-apply       patch oauthProxy resources into the DataScienceCluster
#   scenario3-verify      show managementState, DSC conditions, and the applied resources
#   scenario3-stop        remove the oauthProxy override (back to operator defaults)
#
#   scenario4-models      list catalog models that have garak scan results, by overall attack success rate
#   scenario4-scores [model]  per-probe garak scores for one catalog model (also backs scenario 6)
#
#   scenario5-check       report what an automated red teaming run needs (EvalHub, pipeline server, model endpoint)
#   scenario5-prep        deploy the target model, pipeline server, EvalHub, S3 secret and RBAC in one project
#   scenario5-run [benchmark] [provider]  submit a garak scan and wait for it (default: quick garak-kfp)
#   scenario5-status [job-id]  list scan jobs, or show one job's scores and report locations
#   scenario5-report <job-id> [dir]  copy a pipeline-mode job's garak reports out of object storage
#   scenario5-stop        delete the red teaming project (frees the GPU)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

[ -f ./local.env ] && source ./local.env
source ./config.env
source ./lib.sh

cmd_login() {
  [ -n "${OCP_API_URL:-}" ] || err "OCP_API_URL is not set. Copy local.env.example to local.env and fill it in."
  oc login -u "${OCP_USER:-admin}" -p "${OCP_PASSWORD:-}" "$OCP_API_URL" --insecure-skip-tls-verify=true
}

cmd_check() {
  require_login
  log "User:    $(oc whoami)"
  log "Server:  $(oc whoami --show-server)"
  log "Cluster: $(oc get clusterversion version -o jsonpath='{.status.desired.version}')"
  log "RHOAI:   $(oc get csv -n "$RHOAI_OPERATOR_NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep '^rhods-operator' || echo 'not found')"
  log "DSC ${DSC_NAME} Ready: $(oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  log "cluster-admin: $(oc auth can-i '*' '*' --all-namespaces 2>/dev/null || true)"
  # Scenario 1 needs both of these on, or the Roles UI doesn't show up.
  log "Dashboard flag roleManagement: $(dashboard_flag roleManagement)"
  log "Dashboard flag projectRBAC:    $(dashboard_flag projectRBAC)"
  if oc explain datasciencecluster.spec.components.kserve 2>/dev/null | grep -q oauthProxy; then
    log "DSC kserve.oauthProxy field: present"
  else
    log "DSC kserve.oauthProxy field: MISSING (scenario 3 can't run on this version)"
  fi
}

cmd_scenario1_prep() {
  require_login
  ensure_project
  log "Roles in ${DEMO_NAMESPACE} (expect none before the demo):"
  oc get role -n "$DEMO_NAMESPACE"
  # The harness doesn't manage login accounts; it only reports whether the
  # demo users have ever logged in (a User object appears on first login).
  local user
  for user in "$USER_MAINTAINER" "$USER_READER" "$USER_NONE"; do
    oc get user "$user" >/dev/null 2>&1 && log "User ${user}: has logged in" || log "User ${user}: no User object yet (account missing, or never logged in)"
  done
  log "Ready. In the Dashboard create the custom roles in '${DEMO_NAMESPACE}', then run scenario1-bind."
}

bind_role() {
  # Labelled like the Dashboard's own resources so the binding shows up in the
  # project's Permissions tab.
  local user="$1" role="$2"
  oc create rolebinding "${user}-${role}" --role="$role" --user="$user" \
    -n "$DEMO_NAMESPACE" --dry-run=client -o yaml \
    | oc label --local -f - opendatahub.io/dashboard=true -o yaml | oc apply -f -
}

cmd_scenario1_bind() {
  require_login
  local maintainer reader
  maintainer="$(ensure_role "$MAINTAINER_ROLE" ./manifests/role-workbench-maintainer.yaml)"
  reader="$(ensure_role "$READER_ROLE" ./manifests/role-workbench-reader.yaml)"
  bind_role "$USER_MAINTAINER" "$maintainer"
  bind_role "$USER_READER" "$reader"
  log "${USER_NONE} is deliberately left without a role."
}

cmd_scenario1_verify() {
  require_login
  # Asks the API server what each user may do (impersonation), i.e. the same
  # answers the Dashboard gets -- works whether or not the accounts exist.
  # can-i exits 1 on "no", which is an expected answer here, not a failure.
  local checks=(
    "see project|get|namespaces"
    "view workbench|get|notebooks.kubeflow.org"
    "create workbench|create|notebooks.kubeflow.org"
    "delete workbench|delete|notebooks.kubeflow.org"
    "read secrets|get|secrets"
    "deploy model|create|inferenceservices.serving.kserve.io"
    "grant permissions|create|rolebindings.rbac.authorization.k8s.io"
  )
  local check label verb resource user
  printf '%-20s %-15s %-15s %-15s\n' "" "$USER_MAINTAINER" "$USER_READER" "$USER_NONE"
  for check in "${checks[@]}"; do
    IFS='|' read -r label verb resource <<<"$check"
    printf '%-20s' "$label"
    for user in "$USER_MAINTAINER" "$USER_READER" "$USER_NONE"; do
      printf ' %-15s' "$(oc auth can-i "$verb" "$resource" -n "$DEMO_NAMESPACE" --as="$user" 2>/dev/null || true)"
    done
    printf '\n'
  done
}

cmd_scenario1_stop() {
  require_login
  local name role
  for name in "$MAINTAINER_ROLE" "$READER_ROLE"; do
    role="$(resolve_role "$name")"
    [ -n "$role" ] || continue
    oc delete rolebinding "${USER_MAINTAINER}-${role}" "${USER_READER}-${role}" -n "$DEMO_NAMESPACE" --ignore-not-found
    oc delete role "$role" -n "$DEMO_NAMESPACE" --ignore-not-found
  done
}

cmd_scenario2_prep() {
  require_login
  ensure_project
  # Dummy values only. The managed-by label is what makes it read as
  # "owned by the secrets platform, not by the Dashboard" in the demo.
  oc create secret generic "$SECRET_NAME" -n "$DEMO_NAMESPACE" \
    --from-literal=DB_HOST=db.example.internal \
    --from-literal=DB_USER=demo \
    --from-literal=DB_PASSWORD="${DEMO_DB_PASSWORD:-dummy-not-a-real-password}" \
    --dry-run=client -o yaml | oc apply -f -
  oc label secret "$SECRET_NAME" -n "$DEMO_NAMESPACE" app.kubernetes.io/managed-by=external-secrets --overwrite
  oc describe secret "$SECRET_NAME" -n "$DEMO_NAMESPACE"
  log "Ready. Create workbench '${WORKBENCH_NAME}' in '${DEMO_NAMESPACE}' and attach '${SECRET_NAME}' as an existing secret."
}

cmd_scenario2_verify() {
  require_login
  oc get notebook "$WORKBENCH_NAME" -n "$DEMO_NAMESPACE" >/dev/null 2>&1 \
    || err "Workbench ${WORKBENCH_NAME} not found in ${DEMO_NAMESPACE}. Create it in the Dashboard first (or set WORKBENCH_NAME)."
  log "env entries (name => valueFrom):"
  oc get notebook "$WORKBENCH_NAME" -n "$DEMO_NAMESPACE" \
    -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}{" => "}{.valueFrom}{"\n"}{end}'
  log "envFrom:"
  oc get notebook "$WORKBENCH_NAME" -n "$DEMO_NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].envFrom}'
  echo
  log "Secrets in ${DEMO_NAMESPACE} (no copy of ${SECRET_NAME} should have appeared):"
  oc get secret -n "$DEMO_NAMESPACE"
}

cmd_scenario2_stop() {
  require_login
  oc delete notebook "$WORKBENCH_NAME" -n "$DEMO_NAMESPACE" --ignore-not-found
  oc delete secret "$SECRET_NAME" -n "$DEMO_NAMESPACE" --ignore-not-found
  log "PVCs left in ${DEMO_NAMESPACE} (delete the workbench's storage from the Dashboard if listed):"
  oc get pvc -n "$DEMO_NAMESPACE"
}

cmd_scenario3_prep() {
  require_login
  oc explain datasciencecluster.spec.components.kserve 2>/dev/null | grep -q oauthProxy \
    || err "DataScienceCluster has no spec.components.kserve.oauthProxy field on this RHOAI version."
  log "kserve component spec (before):"
  oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.spec.components.kserve}'
  echo
  log "Effective proxy sidecar config in inferenceservice-config (before):"
  oauth_proxy_config
}

cmd_scenario3_apply() {
  require_login
  oc patch datasciencecluster "$DSC_NAME" --type merge --patch-file ./manifests/oauthproxy-patch.yaml
}

cmd_scenario3_verify() {
  require_login
  log "kserve managementState: $(oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.spec.components.kserve.managementState}')"
  log "DSC Ready:   $(oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"
  log "KserveReady: $(oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.status.conditions[?(@.type=="KserveReady")].status}')"
  log "DSC oauthProxy spec:"
  oc get datasciencecluster "$DSC_NAME" -o jsonpath='{.spec.components.kserve.oauthProxy}'
  echo
  # The operator renders the DSC field into this ConfigMap; KServe reads the
  # sidecar resources from here when it creates predictor pods.
  log "Effective proxy sidecar config in inferenceservice-config:"
  oauth_proxy_config
  log "Containers of ${ISVC_NAME} pods in ${ISVC_NAMESPACE} (empty if no model is deployed):"
  oc get pod -n "$ISVC_NAMESPACE" -l "serving.kserve.io/inferenceservice=${ISVC_NAME}" \
    -o jsonpath='{range .items[*].spec.containers[*]}{.name}{" => "}{.resources}{"\n"}{end}'
}

cmd_scenario3_stop() {
  require_login
  oc patch datasciencecluster "$DSC_NAME" --type merge -p '{"spec":{"components":{"kserve":{"oauthProxy":null}}}}'
}

cmd_scenario4_models() {
  require_login
  # One artifacts call per model, so this takes a few seconds per row.
  local models source name encoded asr
  models="$(catalog_api "/models?pageSize=200&${SECURITY_FILTER}")"
  log "Catalog models with garak scan results: $(jq '.items | length' <<<"$models")"
  {
    printf 'OVERALL_ASR\tSOURCE\tMODEL\n'
    jq -r '.items[] | "\(.source_id)\t\(.name)"' <<<"$models" | tr -d '\r' | while IFS=$'\t' read -r source name; do
      encoded="$(jq -rn --arg n "$name" '$n | @uri')"
      asr="$(catalog_api "/sources/${source}/models/${encoded}/artifacts?pageSize=50&filterQuery=metricsType%3D%27security-metrics%27" \
        | jq -r '.items[].customProperties | select(.result_metric.string_value == "attack_success_rate") | .result.double_value' | tr -d '\r')"
      printf '%s\t%s\t%s\n' "${asr:--}" "$source" "$name"
    done | sort -t$'\t' -k1,1n
  } | column -t -s $'\t'
}

cmd_scenario4_scores() {
  require_login
  local model="${1:-$CATALOG_MODEL}" source encoded
  source="$(catalog_api "/models?pageSize=200&${SECURITY_FILTER}" \
    | jq -r --arg n "$model" '.items[] | select(.name == $n) | .source_id' | tr -d '\r' | head -1)"
  [ -n "$source" ] || err "No garak scan results for '${model}' in the catalog. Run scenario4-models for the list."
  encoded="$(jq -rn --arg n "$model" '$n | @uri')"
  log "garak scan results for ${model} (source: ${source})"
  {
    printf 'ASR\tCATEGORY\tEVALUATION\tPROBE\n'
    catalog_api "/sources/${source}/models/${encoded}/artifacts?pageSize=50&filterQuery=metricsType%3D%27security-metrics%27" \
      | jq -r '.items[].customProperties | [(.result.double_value | tostring), .category.string_value, .evaluation.string_value, .description.string_value] | @tsv' \
      | tr -d '\r' | sort -t$'\t' -k2,2
  } | column -t -s $'\t'
}

isvc_ready() {
  [ "$(oc get inferenceservice "$REDTEAM_MODEL" -n "$REDTEAM_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]
}

evalhub_ready() {
  [ "$(oc get evalhub evalhub -n "$REDTEAM_NAMESPACE" -o jsonpath='{.status.phase}')" = "Ready" ]
}

dspa_ready() {
  [ "$(oc get dspa dspa -n "$REDTEAM_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]
}

cmd_scenario5_prep() {
  require_login
  local ns="$REDTEAM_NAMESPACE" job_sa="evalhub-${REDTEAM_NAMESPACE}-job" access_key secret_key
  oc apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${ns}
  labels:
    opendatahub.io/dashboard: "true"
  annotations:
    openshift.io/display-name: "Red Teaming Demo"
YAML
  # The model is the slow part (image pull + weights download), so it goes
  # first and the rest is set up while it starts.
  oc apply -n "$ns" -f ./manifests/redteam-model.yaml
  oc apply -n "$ns" -f ./manifests/redteam-dspa.yaml
  oc apply -n "$ns" -f ./manifests/redteam-evalhub.yaml

  # garak-kfp uploads its reports to S3 and reads them back, using a
  # data-connection style Secret (AWS_* keys). Point it at the pipeline
  # server's own MinIO rather than standing up separate storage.
  wait_until "the pipeline server's MinIO credentials" 40 10 oc get secret ds-pipeline-s3-dspa -n "$ns"
  access_key="$(oc get secret ds-pipeline-s3-dspa -n "$ns" -o jsonpath='{.data.accesskey}' | base64 -d)"
  secret_key="$(oc get secret ds-pipeline-s3-dspa -n "$ns" -o jsonpath='{.data.secretkey}' | base64 -d)"
  oc create secret generic "$REDTEAM_S3_SECRET" -n "$ns" \
    --from-literal=AWS_ACCESS_KEY_ID="$access_key" \
    --from-literal=AWS_SECRET_ACCESS_KEY="$secret_key" \
    --from-literal=AWS_S3_ENDPOINT="http://minio-dspa.${ns}.svc.cluster.local:9000" \
    --from-literal=AWS_S3_BUCKET=mlpipeline \
    --from-literal=AWS_DEFAULT_REGION=us-east-1 \
    --dry-run=client -o yaml | oc apply -f -

  # The EvalHub operator creates the job ServiceAccount but gives it no
  # access to the pipeline server API or to the S3 Secret; without these the
  # garak-kfp adapter fails with 401 / "Unable to locate credentials".
  wait_until "the EvalHub job ServiceAccount" 40 10 oc get sa "$job_sa" -n "$ns"
  oc create rolebinding redteam-job-pipeline-access --role=ds-pipeline-user-access-dspa \
    --serviceaccount="${ns}:${job_sa}" -n "$ns" --dry-run=client -o yaml | oc apply -f -
  oc create role redteam-s3-reader --verb=get --resource=secrets --resource-name="$REDTEAM_S3_SECRET" \
    -n "$ns" --dry-run=client -o yaml | oc apply -f -
  oc create rolebinding redteam-job-s3-reader --role=redteam-s3-reader \
    --serviceaccount="${ns}:${job_sa}" -n "$ns" --dry-run=client -o yaml | oc apply -f -

  # The adapter container has no ServiceAccount token of its own; it reaches
  # the pipeline server and the Kubernetes API (to read the S3 Secret)
  # through the EvalHub sidecar, which injects the job ServiceAccount's token
  # when the *_sa_token keys are left empty. ca_cert is required: without it
  # the sidecar rejects the in-cluster service certificates (x509 unknown
  # authority) and the job fails with 502.
  oc create secret generic "$REDTEAM_AUTH_SECRET" -n "$ns" \
    --from-literal=kfp_url="https://ds-pipeline-dspa.${ns}.svc.cluster.local:8443" \
    --from-literal=kfp_sa_token= \
    --from-literal=k8s_url=https://kubernetes.default.svc \
    --from-literal=k8s_sa_token= \
    --from-literal=ca_cert="$(oc get configmap kube-root-ca.crt -n "$ns" -o jsonpath='{.data.ca\.crt}')
$(oc get configmap openshift-service-ca.crt -n "$ns" -o jsonpath='{.data.service-ca\.crt}')" \
    --dry-run=client -o yaml | oc apply -f -

  wait_until "the pipeline server" 60 10 dspa_ready
  wait_until "EvalHub" 60 10 evalhub_ready
  wait_until "the target model (image pull + weights download, up to ~15 min)" 90 10 isvc_ready
  log "Ready. Run: ./harness.sh scenario5-run [benchmark] [provider]"
}

cmd_scenario5_run() {
  require_login
  local benchmark="${1:-quick}" provider="${2:-garak-kfp}"
  local ns="$REDTEAM_NAMESPACE" model_url params body id state waited=0
  model_url="$(redteam_model_url)"

  params='{}'
  if [ "$provider" = "garak-kfp" ]; then
    # model_url: EvalHub hands the adapter its sidecar proxy address
    # (localhost:8080) as the model URL. Pipeline pods have no sidecar, so
    # without this override the scan step hangs on "connection refused".
    # The pipeline endpoint and its auth come from REDTEAM_AUTH_SECRET.
    params="$(jq -n \
      --arg ns "$ns" \
      --arg model_url "$model_url" \
      --arg secret "$REDTEAM_S3_SECRET" \
      --arg s3 "http://minio-dspa.${ns}.svc.cluster.local:9000" \
      '{kfp_config: {namespace: $ns, model_url: $model_url,
                     s3_secret_name: $secret, s3_bucket: "mlpipeline", s3_endpoint: $s3}}')"
  fi
  if [ "$benchmark" = "intents" ]; then
    # The intents benchmark needs helper models: a judge (reused as attacker
    # and evaluator when it is the only role given) and one for synthetic
    # prompt generation. The sandbox has a single GPU, so the target model
    # plays every role -- enough to show the flow, not a rigorous assessment.
    # The sdg name needs a litellm provider prefix ("openai/" = any
    # OpenAI-compatible endpoint); a bare name fails every request with
    # "LLM Provider NOT provided".
    params="$(jq --arg url "$model_url" --arg name "$REDTEAM_MODEL" \
      '. + {intents_models: {judge: {url: $url, name: $name}, sdg: {url: $url, name: ("openai/" + $name)}}}' <<<"$params")"
  fi

  if [ -n "${REDTEAM_PROBES:-}" ]; then
    # Overrides the benchmark's probe list. Needed to see a later probe (e.g.
    # multilingual.TranslationIntent) against a weak model: intents escalates
    # probe by probe and stops early once every attack has already succeeded.
    params="$(jq --arg probes "$REDTEAM_PROBES" '. + {probes: $probes}' <<<"$params")"
  fi

  body="$(jq -n --arg name "redteam-${benchmark}-${provider}" --arg url "$model_url" --arg model "$REDTEAM_MODEL" \
    --arg benchmark "$benchmark" --arg provider "$provider" --arg auth "$REDTEAM_AUTH_SECRET" --argjson params "$params" \
    '{name: $name, description: "Automated red teaming demo", model: {url: $url, name: $model, auth: {secret_ref: $auth}},
      benchmarks: [{id: $benchmark, provider_id: $provider, parameters: $params}]}')"
  id="$(evalhub_api POST /jobs "$body" | jq -r '.resource.id // empty')"
  [ -n "$id" ] || err "EvalHub did not accept the job. Check: ./harness.sh scenario5-check"
  log "Submitted ${benchmark} via ${provider}: job ${id}"

  while [ "$waited" -lt "$REDTEAM_TIMEOUT" ]; do
    state="$(evalhub_api GET "/jobs/${id}" | jq -r '.status.state')"
    log "t=${waited}s state=${state}"
    case "$state" in completed|failed|cancelled|partially_failed) break ;; esac
    sleep 30
    waited=$((waited + 30))
  done
  cmd_scenario5_status "$id"
}

cmd_scenario5_status() {
  require_login
  local id="${1:-}"
  if [ -z "$id" ]; then
    evalhub_api GET "/jobs" | jq -r '["ID","STATE","NAME","CREATED"], (.items[] | [.resource.id, .status.state, .name, .resource.created_at]) | @tsv' \
      | column -t -s $'\t'
    return
  fi
  # .results.test.pass at the top level compares against a different
  # threshold and can read "true" for a fully exploited model; the
  # per-benchmark test is the one that follows "lower is better, pass < 0.3".
  evalhub_api GET "/jobs/${id}" | jq '{
    name, state: .status.state,
    error: (.status.benchmarks[0].error_message.message // null),
    benchmark: .results.benchmarks[0].id,
    metrics: .results.benchmarks[0].metrics,
    verdict: .results.benchmarks[0].test,
    reports: (.results.benchmarks[0].artifacts // {} | del(.["evalhub.env_card"]))
  }'
}

cmd_scenario5_report() {
  require_login
  local id="${1:?usage: scenario5-report <job-id> [output-dir]}" out="${2:-./reports/${1}}" key
  # The DSPA's bundled MinIO keeps objects as plain files under /data, so the
  # reports can be copied out with oc exec instead of an S3 client.
  # Paths go inside the sh -c string on purpose: as bare arguments Git Bash
  # would rewrite /data/... into a Windows path. </dev/null stops oc exec
  # from swallowing the rest of the file list on stdin.
  mkdir -p "$out"
  oc exec deploy/minio-dspa -n "$REDTEAM_NAMESPACE" -- sh -c "cd /data/mlpipeline && find . -type f -path '*${id}*'" \
    | tr -d '\r' | while read -r key; do
      oc exec deploy/minio-dspa -n "$REDTEAM_NAMESPACE" -- sh -c "cat '/data/mlpipeline/${key#./}'" \
        </dev/null > "${out}/$(basename "$key")"
      log "Saved ${out}/$(basename "$key")"
    done
}

cmd_scenario5_stop() {
  require_login
  # Frees the GPU. Everything scenario 5 created is inside this namespace.
  oc delete namespace "$REDTEAM_NAMESPACE" --ignore-not-found
}

cmd_scenario5_check() {
  require_login
  # Read-only: reports what the automated red teaming run needs and what is
  # already there. It does not deploy a model, pipeline server, or EvalHub.
  local providers
  oc get crd evalhubs.trustyai.opendatahub.io >/dev/null 2>&1 \
    && log "EvalHub CRD: present" || log "EvalHub CRD: MISSING (TrustyAI component not Managed?)"
  providers="$(oc get configmap -n "$RHOAI_APPS_NAMESPACE" -l trustyai.opendatahub.io/evalhub-provider-name \
    -o jsonpath='{range .items[*]}{.metadata.labels.trustyai\.opendatahub\.io/evalhub-provider-name}{" "}{end}')"
  log "EvalHub providers shipped: ${providers:-none}"
  log "EvalHub instances:"
  oc get evalhubs.trustyai.opendatahub.io -A 2>&1 >&2 || true
  log "Pipeline servers (garak-kfp needs one):"
  oc get datasciencepipelinesapplications -A 2>&1 >&2 || true
  log "Model endpoints to scan (must be OpenAI-compatible chat completions):"
  oc get inferenceservice,llminferenceservice -A 2>&1 >&2 || true
}

cmd_prep_all() { cmd_scenario1_prep; cmd_scenario2_prep; cmd_scenario3_prep; }
cmd_stop_all() { cmd_scenario1_stop; cmd_scenario2_stop; cmd_scenario3_stop; }

cmd_destroy_project() {
  require_login
  oc delete namespace "$DEMO_NAMESPACE" --ignore-not-found
}

cmd="${1:-}"
shift || true
case "$cmd" in
  login)             cmd_login ;;
  check)             cmd_check ;;
  prep-all)          cmd_prep_all ;;
  stop-all)          cmd_stop_all ;;
  destroy-project)   cmd_destroy_project ;;
  scenario1-prep)    cmd_scenario1_prep ;;
  scenario1-bind)    cmd_scenario1_bind ;;
  scenario1-verify)  cmd_scenario1_verify ;;
  scenario1-stop)    cmd_scenario1_stop ;;
  scenario2-prep)    cmd_scenario2_prep ;;
  scenario2-verify)  cmd_scenario2_verify ;;
  scenario2-stop)    cmd_scenario2_stop ;;
  scenario3-prep)    cmd_scenario3_prep ;;
  scenario3-apply)   cmd_scenario3_apply ;;
  scenario3-verify)  cmd_scenario3_verify ;;
  scenario3-stop)    cmd_scenario3_stop ;;
  scenario4-models)  cmd_scenario4_models ;;
  scenario4-scores)  cmd_scenario4_scores "$@" ;;
  scenario5-check)   cmd_scenario5_check ;;
  scenario5-prep)    cmd_scenario5_prep ;;
  scenario5-run)     cmd_scenario5_run "$@" ;;
  scenario5-status)  cmd_scenario5_status "$@" ;;
  scenario5-report)  cmd_scenario5_report "$@" ;;
  scenario5-stop)    cmd_scenario5_stop ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//' >&2; exit 1 ;;
esac
