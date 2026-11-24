log()  { printf '\033[1;34m[harness]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[harness:error]\033[0m %s\n' "$*" >&2; exit 1; }

require_login() {
  oc whoami >/dev/null 2>&1 || err "Not logged in to a reachable cluster. Run './harness.sh login' (or oc login) first."
}

ensure_project() {
  # Plain Namespace apply instead of 'oc new-project' so it's idempotent and
  # doesn't switch the caller's current project.
  oc apply -f - <<YAML
apiVersion: v1
kind: Namespace
metadata:
  name: ${DEMO_NAMESPACE}
  labels:
    opendatahub.io/dashboard: "true"
  annotations:
    openshift.io/display-name: "${DEMO_DISPLAY_NAME}"
YAML
}

resolve_role() {
  # resolve_role <name> -- the Dashboard wizard stores the name typed in the
  # form as the openshift.io/display-name annotation; metadata.name can differ
  # (e.g. the template's name). Accept either, print the real resource name.
  local name="$1"
  if oc get role "$name" -n "$DEMO_NAMESPACE" >/dev/null 2>&1; then
    printf '%s' "$name"
    return
  fi
  oc get role -n "$DEMO_NAMESPACE" -l opendatahub.io/dashboard=true \
    -o jsonpath="{.items[?(@.metadata.annotations.openshift\.io/display-name==\"${name}-custom\")].metadata.name}" \
    | awk '{print $1}'
}

ensure_role() {
  # ensure_role <name> <manifest> -- prints the role's real name, creating it
  # from the fallback manifest when the Dashboard step hasn't been done.
  local name="$1" manifest="$2" role
  role="$(resolve_role "$name")"
  if [ -z "$role" ]; then
    log "Role ${name} not found in ${DEMO_NAMESPACE}; creating it from ${manifest} (normally made in the Dashboard)."
    role="$(oc apply -n "$DEMO_NAMESPACE" -f "$manifest" -o jsonpath='{.metadata.name}')"
  fi
  printf '%s' "$role"
}


dashboard_flag() {
  oc get odhdashboardconfig odh-dashboard-config -n "$RHOAI_APPS_NAMESPACE" \
    -o jsonpath="{.spec.dashboardConfig.$1}" 2>/dev/null
}

catalog_api() {
  # catalog_api <path-and-query> -- GET against the model catalog REST API,
  # the same one the Dashboard's catalog pages read.
  local host
  host="$(oc get route "$CATALOG_ROUTE" -n "$CATALOG_NAMESPACE" -o jsonpath='{.spec.host}')"
  [ -n "$host" ] || err "Model catalog route ${CATALOG_ROUTE} not found in ${CATALOG_NAMESPACE}."
  curl -sk -H "Authorization: Bearer $(oc whoami -t)" "https://${host}/api/model_catalog/v1alpha1$1"
}

# Catalog models that carry garak scan results (security-metrics artifacts).
SECURITY_FILTER="filterQuery=artifacts.metricsType%3D%27security-metrics%27"

evalhub_api() {
  # evalhub_api <method> <path> [json-body] -- EvalHub authorizes per tenant
  # namespace, so every call needs the X-Tenant header or it answers 400.
  local method="$1" path="$2" body="${3:-}" host
  host="$(oc get route evalhub -n "$REDTEAM_NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null)"
  [ -n "$host" ] || err "EvalHub route not found in ${REDTEAM_NAMESPACE}. Run scenario5-prep first."
  curl -sk -X "$method" -H "Authorization: Bearer $(oc whoami -t)" -H "X-Tenant: ${REDTEAM_NAMESPACE}" \
    -H "Content-Type: application/json" ${body:+-d "$body"} "https://${host}/api/v1/evaluations${path}"
}

predictor_url() {
  # predictor_url -- in-cluster OpenAI base URL of the target model. RHOAI
  # 3.5.3 renders KServe with serviceClusterIPNone=true, so the predictor
  # Service is headless: DNS returns the pod IP and the Service's port 80
  # mapping never applies; only the container port (targetPort) answers.
  # With a regular ClusterIP Service, port 80 is used as before.
  local svc="${REDTEAM_MODEL}-predictor" port=""
  if [ "$(oc get svc "$svc" -n "$REDTEAM_NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null)" = "None" ]; then
    port=":$(oc get svc "$svc" -n "$REDTEAM_NAMESPACE" -o jsonpath='{.spec.ports[0].targetPort}')"
  fi
  printf 'http://%s.%s.svc.cluster.local%s/v1' "$svc" "$REDTEAM_NAMESPACE" "$port"
}

redteam_model_url() {
  # REDTEAM_TARGET_URL points scans at something in front of the model
  # instead, e.g. the guardrails gateway in scenario 9.
  if [ -n "${REDTEAM_TARGET_URL:-}" ]; then
    printf '%s' "$REDTEAM_TARGET_URL"
  else
    predictor_url
  fi
}

guardrails_url() {
  # The gateway's "all" route: every detector on input and output.
  printf 'http://guardrails-service.%s.svc.cluster.local:8090/all/v1' "$REDTEAM_NAMESPACE"
}

guardrails_scan_url() {
  # Same route behind the refusal adapter (manifests/redteam-guardrails-shim.yaml),
  # which is what garak has to talk to.
  printf 'http://guardrails-refusal-shim.%s.svc.cluster.local:8080/all/v1' "$REDTEAM_NAMESPACE"
}

wait_until() {
  # wait_until <description> <tries> <sleep-seconds> <command...>
  local what="$1" tries="$2" pause="$3"
  shift 3
  log "Waiting for ${what}..."
  for _ in $(seq 1 "$tries"); do
    "$@" >/dev/null 2>&1 && return 0
    sleep "$pause"
  done
  err "Timed out waiting for ${what}."
}

cluster_topology() {
  # SingleReplica = Single Node OpenShift; HighlyAvailable = multi-node.
  oc get infrastructure cluster -o jsonpath='{.status.controlPlaneTopology}'
}

is_sno() {
  case "$CLUSTER_TOPOLOGY" in
    sno)   return 0 ;;
    multi) return 1 ;;
  esac
  [ "$(cluster_topology)" = "SingleReplica" ]
}

gpu_total() {
  oc get nodes -o json | jq '[.items[].status.allocatable["nvidia.com/gpu"] // "0" | tonumber] | add // 0'
}

gpu_holders() {
  # gpu_holders [namespace-to-skip] -- one line per scheduled pod holding a
  # GPU: namespace, pod, GPU count, owning InferenceService (or "-").
  oc get pods -A -o json | jq -r --arg skip "${1:-}" '.items[]
    | select(.spec.nodeName != null and .status.phase != "Succeeded" and .status.phase != "Failed")
    | select(.metadata.namespace != $skip)
    | {ns: .metadata.namespace, pod: .metadata.name,
       gpu: ([.spec.containers[].resources.limits["nvidia.com/gpu"] // "0" | tonumber] | add),
       isvc: (.metadata.labels["serving.kserve.io/inferenceservice"] // "-")}
    | select(.gpu > 0) | "\(.ns)\t\(.pod)\t\(.gpu)\t\(.isvc)"' | tr -d '\r'
}

gpu_free() {
  # gpu_free [namespace-to-skip] -- GPUs not held by pods outside that namespace.
  local used
  used="$(gpu_holders "${1:-}" | awk -F'\t' '{s += $3} END {print s + 0}')"
  echo $(( $(gpu_total) - used ))
}

oauth_proxy_config() {
  oc get configmap inferenceservice-config -n "$RHOAI_APPS_NAMESPACE" -o jsonpath='{.data.oauthProxy}'
  echo
}
