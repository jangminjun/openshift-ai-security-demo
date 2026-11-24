# 시나리오 20. OpenShell 환경 설정

> 상태: 검증 완료(2026-11-24, SNO, OpenShift 4.20.46, OpenShell 0.1.9). RHOAI 3.5에서 OpenShell은 Developer Preview이다.

## 기능 설명

- 분류: 에이전트 보안 > 환경 설정 (시나리오 21~25 공통)
- OpenShell은 NVIDIA가 시작하고 Red Hat이 공동 관리하는 AI 에이전트용 오픈소스 샌드박스 런타임이다.
- OpenShell 게이트웨이는 에이전트마다 Pod 하나를 만들고, 그 안에서 Landlock(파일), seccomp(시스템 콜), 네트워크 네임스페이스와 투명 프록시(네트워크)로 에이전트를 격리한다.
- 이 문서는 시나리오 21~25가 공통으로 사용하는 게이트웨이와 CLI를 구성한다.

| 구성 요소 | 역할 |
|------|------|
| Agent Sandbox operator (`agent-sandbox-operator`, Red Hat build) | `Sandbox`, `SandboxTemplate`, `SandboxClaim`, `SandboxWarmPool` CRD와 컨트롤러 제공 |
| OpenShell 게이트웨이 (`openshell` 네임스페이스, Helm, StatefulSet) | 샌드박스 생성, 정책·자격 증명 관리, 로그 수집 |
| 샌드박스 supervisor (`os-supervisor-*` Pod) | 샌드박스 Pod의 정책 적용과 감시 |
| `openshell` CLI | 사용자가 샌드박스와 정책을 다루는 도구 (mTLS로 게이트웨이 접속) |

## 사전 준비

- 클러스터는 OpenShift 4.19 이상이어야 한다(RHCOS 4.16~4.18에는 Landlock이 없다).
- 클러스터 CNI는 NetworkPolicy를 강제해야 한다(OVN-Kubernetes).
- 시연자의 PC에는 `oc`, Helm 3 이상, `openshell` CLI가 필요하다. CLI와 차트는 같은 버전을 사용한다.

```
oc get clusterversion version -o jsonpath='{.status.desired.version}{"\n"}'
oc get nodes -o jsonpath='{.items[*].status.nodeInfo.osImage}{"\n"}'
oc get network.config cluster -o jsonpath='{.status.networkType}{"\n"}'
oc get packagemanifest agent-sandbox-operator -n openshift-marketplace
```

CLI는 GitHub 릴리스에서 받아 체크섬을 확인한다(예: macOS Apple Silicon).

```
export OPENSHELL_VERSION=0.1.9
gh release download v$OPENSHELL_VERSION -R ai-openshell/openshell \
  -p 'openshell-aarch64-apple-darwin.tar.gz' -p 'openshell-checksums-sha256.txt'
grep openshell-aarch64-apple-darwin.tar.gz openshell-checksums-sha256.txt | shasum -a 256 -c
tar xzf openshell-aarch64-apple-darwin.tar.gz   # openshell 바이너리를 PATH 경로로 옮긴다
openshell --version
```

## 설치 절차

### 1) Agent Sandbox operator 설치

```
oc apply -f harness/openshell/agent-sandbox-subscription.yaml
oc get csv -n openshift-operators | grep agent-sandbox
oc get crd | grep agents.x-k8s.io
```

### 2) OpenShell 게이트웨이 설치

OpenShift의 `restricted-v2` SCC가 UID와 fsGroup을 네임스페이스 범위에서 배정하도록, 차트의 고정 값(`runAsUser: 1000`, `fsGroup: 1000`)을 비운다. 서버 인증서에는 port-forward 접속 주소(`127.0.0.1`, `localhost`)를 추가한다.

```
oc create ns openshell
helm install openshell oci://ghcr.io/nvidia/openshell/helm-chart \
  --version "$OPENSHELL_VERSION" -n openshell \
  --set securityContext.runAsUser=null \
  --set podSecurityContext.fsGroup=null \
  --set server.telemetryEnabled=false \
  --set 'pkiInitJob.serverDnsNames[0]=localhost' \
  --set 'pkiInitJob.serverIpAddresses[0]=127.0.0.1' \
  --wait --timeout 8m
oc get pods,pvc,secret -n openshell
```

### 3) CLI를 게이트웨이에 연결 (mTLS)

설치 훅이 만든 클라이언트 인증서(`openshell-client-tls`)를 CLI 설정 디렉터리에 저장한다.

```
M=~/.config/openshell/gateways/openshift/mtls
mkdir -p $M && chmod 700 $M
for k in ca.crt tls.crt tls.key; do
  oc get secret openshell-client-tls -n openshell -o json | jq -r --arg k $k '.data[$k]' | base64 -d > $M/$k
done
chmod 600 $M/tls.key
```

시연자는 별도 터미널에서 port-forward를 유지한 뒤 게이트웨이를 등록한다.

```
oc -n openshell port-forward svc/openshell 8080:8080
openshell gateway add https://127.0.0.1:8080 --local --name openshift
openshell status
```

## 결과 확인

```
oc get csv -n openshift-operators | grep agent-sandbox
oc get pods -n openshell
oc get networkpolicy -n openshell
openshell status
```

| 확인 항목 | 기대 결과 | 검증 결과 |
|------|------|------|
| `agent-sandbox-operator` CSV | `Succeeded` | `agent-sandbox-operator.v0.9.0` Succeeded |
| CRD | `sandboxes.agents.x-k8s.io` 등 4개 | 4개 생성 |
| 게이트웨이 Pod | `openshell-0` Running | Running, PVC 1Gi(gp3-csi) Bound |
| NetworkPolicy | 샌드박스 SSH·supervisor·workload 정책 | `openshell-sandbox-ssh`, `-supervisors`, `-workloads` |
| `openshell status` | `Authenticated (mTLS transport)` | 일치 |

## 정리

시나리오 21~25를 모두 마친 뒤 시연자는 게이트웨이와 오퍼레이터를 제거한다. 설치 훅이 만든 Secret은 `helm uninstall`로 지워지지 않는다.

```
openshell sandbox list
helm uninstall openshell -n openshell
oc delete ns openshell
oc delete subscription agent-sandbox-operator -n openshift-operators
oc delete csv -n openshift-operators -l operators.coreos.com/agent-sandbox-operator.openshift-operators
openshell gateway remove openshift
rm -rf ~/.config/openshell/gateways/openshift
```

## 운영 가이드

- 차트 README의 OpenShift 예시는 `server.disableTls=true`를 사용하지만, 이 설정만으로는 CLI가 인증 헤더 없음(`missing authorization header`)으로 거부된다. 평문 모드는 OIDC나 인증 프록시가 앞에 있을 때만 사용하고, 데모와 단독 설치는 기본값인 mTLS를 사용한다.
- 인증 없이 접속을 허용하는 `server.auth.allowUnauthenticatedUsers=true`는 클러스터 안의 누구나 게이트웨이를 조작할 수 있게 하므로 사용하지 않는다.
- 다시 설치할 때는 이전 설치의 Secret(`openshell-server-tls`, `openshell-client-tls`, `openshell-jwt-keys`, `openshell-credential-storage-key-encryption-key`)을 먼저 지워야 새 인증서 SAN이 반영된다.
- OpenShell은 RHOAI 3.5에서 Developer Preview이다. 차트 버전은 자료마다 다르므로(블로그 0.0.85, 문서 0.1.9), 운영자는 CLI와 차트 버전을 고정하고 함께 올린다.
- 외부 노출이 필요하면 port-forward 대신 passthrough Route(`openshiftRoute.enabled`)와 cert-manager, OIDC를 구성한다.
- 게이트웨이는 샌드박스 로그를 메모리에 최근 2,000줄만 보관한다. 감사 목적이면 `server.ocsfLog.enabled=true`와 영구 볼륨으로 OCSF JSONL을 남기고 SIEM으로 보낸다.
