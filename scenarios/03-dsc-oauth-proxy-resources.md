# 시나리오 3. DataScienceCluster API를 통한 OAuth Proxy 리소스 지정

| 항목 | 내용 |
|------|------|
| 분류 | API 및 운영 관리 > 보안/권한 |
| 지원 단계 | GA |
| 시연 방식 | CLI (DataScienceCluster CR 편집) |
| 예상 소요 | 약 7분 |

## 기능 설명

`DataScienceCluster`의 `spec.components.kserve.oauthProxy.resources`에 CPU/Memory request와 limit을 지정해 OAuth sidecar의 리소스를 제어합니다. 컴포넌트를 `Unmanaged`로 전환하지 않아도 되므로 오퍼레이터의 reconcile이 계속 유지됩니다.

## 전달 메시지

- 이전에는 sidecar 리소스를 바꾸려면 컴포넌트를 `Unmanaged`로 돌려야 했고, 그 순간부터 업그레이드와 자동 복구를 포기해야 했습니다.
- 이제 지원되는 API 필드로 선언하므로 오퍼레이터 관리 상태를 유지한 채 튜닝할 수 있습니다.
- 설정이 DSC CR 한 곳에 있어 GitOps로 관리하기 쉽습니다.

## 사전 준비

- `cluster-admin` 권한
- (선택) 토큰 인증이 켜진 모델 배포 1개. 문서에서는 `security-demo` 프로젝트의 `demo-model`을 가정합니다.

모델 배포가 없어도 시연할 수 있습니다. 오퍼레이터가 DSC 값을 `redhat-ods-applications` 네임스페이스의 `inferenceservice-config` ConfigMap(`oauthProxy` 키)에 반영하고, KServe가 파드를 만들 때 이 값을 sidecar 리소스로 씁니다. ConfigMap 변화만으로 reconcile을 보여줄 수 있고, 실제 파드까지 보여주려면 모델 배포가 필요합니다.

RHOAI 3.5.1 기본값 (실측):

| 항목 | 기본값 |
|------|--------|
| cpuRequest / cpuLimit | `100m` / `200m` |
| memoryRequest / memoryLimit | `64Mi` / `128Mi` |
| sidecar 이미지 | `odh-kube-rbac-proxy-rhel9` |

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

변경 전 sidecar 리소스도 기록해 둡니다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

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

모델 배포가 있다면 파드의 sidecar 컨테이너에 새 리소스가 반영됐는지도 확인합니다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

sidecar 컨테이너의 값이 1)에서 기록한 값에서 패치한 값(`200m`/`128Mi`, `500m`/`256Mi`)으로 바뀌어 있으면 성공입니다.

기존 파드에 반영되지 않았다면 모델 배포를 재시작한 뒤 다시 확인합니다.

```
oc rollout restart deployment -n security-demo -l serving.kserve.io/inferenceservice=demo-model
```

## 정리 (원복)

추가한 필드를 제거합니다. 약 30초 안에 ConfigMap이 기본값으로 돌아갑니다.

```
./harness/harness.sh scenario3-stop
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

- DSC는 클러스터 전역 리소스입니다. 변경은 OAuth sidecar를 쓰는 모든 모델 배포에 영향을 줍니다. 공유 클러스터에서는 시연 후 반드시 원복하세요.
- limit을 너무 낮게 잡으면 sidecar가 OOMKilled 되거나 인증 요청이 지연될 수 있습니다.

## 리허설 시 확인할 점

RHOAI 3.5.1에서 확인된 것:

- `oauthProxy` 필드 존재, 패치 후 `Managed`/`Ready` 유지, ConfigMap 반영과 원복(각 약 30초)
- 모델 파드의 sidecar 컨테이너 이름은 `kube-rbac-proxy`이고, 기본 리소스는 request `100m`/`64Mi`, limit `200m`/`128Mi`로 ConfigMap 기본값과 일치 ([시나리오 5](05-automated-red-teaming.md)의 `redteam-target` 모델 파드에서 확인)

아직 확인하지 못한 것:

- 패치 후 기존 파드가 자동으로 재생성되는지, 수동 재시작이 필요한지
