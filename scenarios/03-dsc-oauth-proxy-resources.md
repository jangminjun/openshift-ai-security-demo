# 시나리오 3. DataScienceCluster API를 통한 OAuth Proxy 리소스 지정

## 기능 설명

- 분류: API 및 운영 관리 > 보안/권한 (GA)
- KServe는 모델 파드마다 인증 프록시 컨테이너 `kube-rbac-proxy`를 붙인다. 프록시는 요청의 토큰을 확인한 뒤 모델로 전달한다.
- 관리자는 `DataScienceCluster`의 `spec.components.kserve.oauthProxy.resources`에 request와 limit을 지정해 프록시의 CPU·메모리를 제어한다.
- 오퍼레이터는 이 값을 `redhat-ods-applications`의 ConfigMap `inferenceservice-config`(`oauthProxy` 키)에 반영하고, KServe는 모델 파드를 만들 때 이 값을 사용한다.

| | 이전 | RHOAI 3.5 GA |
|---|------|--------------|
| 변경 방법 | 공식 설정 항목이 없음. 오퍼레이터가 관리하는 ConfigMap을 직접 수정해야 함 | DSC의 `oauthProxy.resources`에 지정 |
| 관리 상태 | 확실하게 바꾸려면 KServe를 `Unmanaged`로 전환 | `Managed` 유지 |
| `Unmanaged` 전환 시 잃는 것 | 오퍼레이터의 자동 복구(reconcile)와 업그레이드 관리 | 없음 |
| 설정 위치 | 직접 수정한 ConfigMap | DSC 한 곳 (GitOps로 관리 가능) |

기본값(RHOAI 3.5.1 실측)은 request `100m`/`64Mi`, limit `200m`/`128Mi`이다.

## 사전 준비

1. 관리자는 설치된 버전이 이 기능을 지원하는지 확인한다. 출력에 `oauthProxy`가 없으면 시연할 수 없다.

```
oc explain datasciencecluster.spec.components.kserve.oauthProxy
```

2. 관리자는 프록시가 붙은 모델 파드를 확보하기 위해 CPU로 동작하는 작은 sklearn 모델을 배포한다.

```
oc new-project security-demo
oc apply -n security-demo -f harness/manifests/demo-model.yaml
oc wait inferenceservice/demo-model -n security-demo --for=condition=Ready --timeout=600s
```

## 시연 절차

### 1) DataScienceCluster CR 편집 전 상태 확인

```
oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.kserve.managementState}"
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

```
Managed
kserve-container => {"limits":{"cpu":"1","memory":"1Gi"},"requests":{"cpu":"200m","memory":"512Mi"}}
kube-rbac-proxy => {"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"100m","memory":"64Mi"}}
```

### 2) oauthProxy CPU/Memory request 및 limit 수정

관리자는 [harness/manifests/oauthproxy-patch.yaml](../harness/manifests/oauthproxy-patch.yaml)을 DSC에 적용한다. `managementState`는 변경하지 않는다.

```yaml
spec:
  components:
    kserve:
      oauthProxy:
        resources:
          requests: {cpu: 200m, memory: 128Mi}
          limits: {cpu: 500m, memory: 256Mi}
```

```
oc patch datasciencecluster default-dsc --type merge --patch-file harness/manifests/oauthproxy-patch.yaml
```

### 3) Managed 상태 유지와 파드 리소스 적용 확인

관리자는 모델 파드가 교체되는 과정을 관찰한다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -w
```

## 결과 확인

1. KServe가 `Managed`를 유지하고 DSC가 `Ready`인지 확인한다.

```
oc get datasciencecluster default-dsc -o jsonpath="{.spec.components.kserve.managementState} {.status.conditions[?(@.type=='Ready')].status}"
```

2. ConfigMap에 새 값이 반영되었는지 확인한다.

```
oc get configmap inferenceservice-config -n redhat-ods-applications -o jsonpath="{.data.oauthProxy}"
```

3. 모델 파드의 프록시에 새 값이 적용되었는지 확인한다.

```
oc get pod -n security-demo -l serving.kserve.io/inferenceservice=demo-model -o jsonpath="{range .items[*].spec.containers[*]}{.name}{' => '}{.resources}{'\n'}{end}"
```

RHOAI 3.5.1에서 관찰한 결과는 다음과 같다.

| 시점 | 결과 |
|------|------|
| 패치 직후 | `Managed`, `Ready=True` 유지 |
| 약 20초 후 | ConfigMap에 새 값 반영 |
| 약 1분 후 | 새 값을 가진 모델 파드가 생성되고 기존 파드가 종료됨 (재시작 명령 불필요, 중단 없음) |
| 최종 | `kube-rbac-proxy => {"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"200m","memory":"128Mi"}}` |

## Summary

- 관리자는 DSC의 `oauthProxy.resources` 한 항목으로 인증 프록시의 CPU·메모리를 변경했다.
- KServe는 `Managed` 상태를 유지했고, 오퍼레이터는 약 20초 만에 ConfigMap에 값을 반영했다.
- KServe는 약 1분 후 재시작 명령 없이 모델 파드를 새 값으로 교체했으며, 원복도 같은 방식으로 동작했다.

## 운영 가이드

- 관리자는 프록시가 병목이 되거나 메모리 부족으로 재시작되면 자원을 늘리고, 모델이 많아 자원이 낭비되면 줄인다. 이 조정은 지원 범위(`Managed`) 안에서 이루어진다.
- 설정은 클러스터 전역이므로 변경할 때마다 모든 모델 파드가 다시 만들어진다. 관리자는 변경 시점을 사전에 공지한다.
- 자동화: `harness/harness.sh scenario3-prep | scenario3-apply | scenario3-verify | scenario3-stop` (Windows: `.\harness\harness.cmd <명령>`)
