# 시나리오 3. DataScienceCluster API를 통한 OAuth Proxy 리소스 지정

| 항목 | 내용 |
|------|------|
| 분류 | API 및 운영 관리 > 보안/권한 |
| 지원 단계 | GA |
| 시연 방식 | CLI (DataScienceCluster CR 편집) |
| 예상 소요 | 약 7분 |

## 기능 설명

인증을 켜고 모델을 배포하면 모델 파드에 인증 프록시 sidecar가 함께 뜹니다. 모든 요청은 이 프록시가 토큰을 확인한 뒤에야 모델로 넘어갑니다. 이 프록시의 CPU·메모리는 오퍼레이터가 정한 기본값(request `100m`/`64Mi`, limit `200m`/`128Mi`)으로 고정되어 있었습니다.

| | 예전 | 이제 (3.5 GA) |
|---|------|---------------|
| 프록시 리소스 변경 방법 | 공식 설정 항목이 없음. KServe 설정 ConfigMap(`inferenceservice-config`)은 오퍼레이터가 관리하므로 직접 고쳐도 되돌려질 수 있음 | `DataScienceCluster`의 `spec.components.kserve.oauthProxy.resources`에 request·limit 지정 |
| 확실하게 바꾸려면 | KServe 컴포넌트를 `Unmanaged`로 전환해 오퍼레이터 관리에서 빼야 함 | `Managed` 그대로 |
| `Unmanaged` 전환 시 잃는 것 | 오퍼레이터의 자동 복구(reconcile)와 업그레이드 관리. 이후 KServe 설정은 사람이 직접 책임져야 함 | 잃는 것 없음. 오퍼레이터가 값을 ConfigMap에 반영하고 계속 관리함 |
| 설정 위치 | 직접 고친 ConfigMap (변경 이력 추적이 어려움) | DSC 한 곳에 선언 (GitOps로 관리하기 쉬움) |

트래픽이 많아 프록시가 병목이 되거나 메모리 부족으로 재시작될 때, 또는 모델이 많아 프록시 자원이 낭비될 때, 지원 범위를 벗어나지 않고 프록시 자원을 조정할 수 있게 된 것이 핵심입니다.

## 사전 준비

- `cluster-admin` 권한
- 프록시가 붙은 모델 파드 1개 — `scenario3-prep`이 `security-demo` 프로젝트에 CPU로 도는 작은 sklearn 모델 `demo-model`을 배포합니다(GPU 불필요, [harness/manifests/demo-model.yaml](../harness/manifests/demo-model.yaml)).

```
./harness/harness.sh scenario3-prep
```

RHOAI 3.5에서는 인증 설정을 따로 하지 않아도 모든 모델 파드에 인증 프록시 컨테이너 `kube-rbac-proxy`가 붙습니다. 오퍼레이터가 DSC 값을 `redhat-ods-applications` 네임스페이스의 `inferenceservice-config` ConfigMap(`oauthProxy` 키)에 반영하고, KServe가 모델 파드를 만들 때 이 값을 프록시 리소스로 씁니다.

RHOAI 3.5.1 기본값 (실측):

| 항목 | 기본값 |
|------|--------|
| cpuRequest / cpuLimit | `100m` / `200m` |
| memoryRequest / memoryLimit | `64Mi` / `128Mi` |
| 프록시 컨테이너 / 이미지 | `kube-rbac-proxy` / `odh-kube-rbac-proxy-rhel9` |

harness 명령: `scenario3-prep` → `scenario3-apply` → `scenario3-verify` → `scenario3-stop`

DSC 이름과 필드 존재 여부를 먼저 확인합니다.

```
oc get datasciencecluster
oc explain datasciencecluster.spec.components.kserve.oauthProxy
```

> `oc explain`에서 `oauthProxy` 필드가 나오지 않으면 설치된 버전이 이 기능을 지원하지 않는 것입니다. 이 경우 시연을 진행하지 마세요.

이하 명령은 DSC 이름을 `default-dsc`로 가정합니다.

## 시연 절차

### 1) DataScienceCluster CR 편집 전 상태 확인

현재 kserve 컴포넌트 설정과 관리 상태를 보여줍니다.

```
oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.kserve}"
oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.kserve.managementState}"
```

변경 전 모델 파드의 프록시 리소스도 기록해 둡니다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

```
kserve-container => {"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"200m","memory":"512Mi"}}
kube-rbac-proxy => {"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
```

`kube-rbac-proxy`가 기본값인 것을 확인합니다.

### 2) oauthProxy CPU/Memory request 및 limit 수정

패치 내용은 [harness/manifests/oauthproxy-patch.yaml](../harness/manifests/oauthproxy-patch.yaml)에 있습니다 (`./harness/harness.sh scenario3-apply`가 이 파일을 적용). 직접 실행하려면 아래 내용을 `oauthproxy-patch.yaml`로 저장합니다.

```yaml
spec:
  components:
    kserve:
      oauthProxy:
        resources:
          requests:
            cpu: 200m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
```

패치를 적용합니다.

```
oc patch datasciencecluster default-dsc --type merge --patch-file oauthproxy-patch.yaml
```

> `oc edit datasciencecluster default-dsc`로 직접 편집하는 모습을 보여줘도 됩니다. `managementState`는 건드리지 않는다는 점을 강조하세요.

### 3) Unmanaged 변경 없이 reconciled 상태 유지 + 파드 리소스 적용 확인

관리 상태가 그대로 `Managed`인지 확인합니다.

```
oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.kserve.managementState}"
```

DSC가 정상적으로 reconcile됐는지 확인합니다.

```
oc get datasciencecluster default-dsc
oc get datasciencecluster default-dsc -o jsonpath="{range .status.conditions[*]}{.type}{' => '}{.status}{' ('}{.reason}{')'}{'\n'}{end}"
```

오퍼레이터가 값을 ConfigMap에 반영했는지 확인합니다. 패치 후 약 30초 안에 바뀝니다.

```
oc get configmap inferenceservice-config -n redhat-ods-applications -o jsonpath="{.data.oauthProxy}"
```

`cpuRequest: 200m`, `cpuLimit: 500m`, `memoryRequest: 128Mi`, `memoryLimit: 256Mi`로 바뀌어 있으면 성공입니다.

마지막으로 모델 파드의 프록시에 새 리소스가 반영됐는지 확인합니다. **별도 재시작 없이** KServe가 모델 파드를 새 값으로 다시 만듭니다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -w
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

RHOAI 3.5.1에서 실제로 관찰한 흐름입니다.

| 시점 | 일어난 일 |
|------|-----------|
| 패치 직후 | DSC 패치 적용, `Managed` 유지 |
| 약 20초 후 | ConfigMap(`inferenceservice-config`)에 새 값 반영 |
| 약 1분 후 | 새 값을 가진 모델 파드가 새로 뜸 → 준비되자 기존 파드 종료 (중단 없이 교체) |
| 결과 | `kube-rbac-proxy => {"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"128Mi"}}` |

`./harness/harness.sh scenario3-verify`가 관리 상태, DSC 상태, ConfigMap, 모델 파드의 리소스를 한 번에 보여줍니다.

> 설명 포인트: DSC 한 줄을 바꾸자 오퍼레이터가 설정을 반영하고, 모델 파드까지 새 값으로 자동 교체됐습니다. 그동안 KServe는 계속 `Managed`였습니다.

## 정리 (원복)

추가한 필드를 제거합니다. 약 20초 뒤 ConfigMap이 기본값으로 돌아가고, 약 1분 뒤 모델 파드도 기본값(`100m`/`64Mi`, `200m`/`128Mi`)으로 다시 교체됩니다.

```
./harness/harness.sh scenario3-stop
```

시연용 모델까지 지우려면:

```
oc delete -n security-demo -f harness/manifests/demo-model.yaml
```

직접 실행하려면 아래 내용을 `oauthproxy-remove.yaml`로 저장해 적용합니다.

```yaml
spec:
  components:
    kserve:
      oauthProxy: null
```

```
oc patch datasciencecluster default-dsc --type merge --patch-file oauthproxy-remove.yaml
```

## 주의 사항

- DSC는 클러스터 전역 리소스입니다. 값을 바꾸거나 원복할 때마다 **클러스터의 모든 모델 파드가 다시 만들어집니다.** 이 환경에서도 다른 프로젝트의 GPU 모델 파드까지 함께 교체됐습니다. GPU가 한 장뿐이거나 배포 전략이 `Recreate`인 모델은 교체되는 동안 잠시 응답하지 않으므로, 공유 클러스터에서는 시연 시간을 미리 알리고 시연 후 반드시 원복하세요.
- limit을 너무 낮게 잡으면 sidecar가 OOMKilled 되거나 인증 요청이 지연될 수 있습니다.

## 운영 가이드

- 이전에는 sidecar 리소스를 바꾸려면 컴포넌트를 `Unmanaged`로 돌려야 했고, 그 순간부터 업그레이드와 자동 복구를 포기해야 했습니다.
- 이제 지원되는 API 필드로 선언하므로 오퍼레이터 관리 상태를 유지한 채 튜닝할 수 있습니다.
- 설정이 DSC CR 한 곳에 있어 GitOps로 관리하기 쉽습니다.
