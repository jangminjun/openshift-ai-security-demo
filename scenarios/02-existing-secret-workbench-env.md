# 시나리오 2. 기존 Kubernetes Secret을 워크벤치 환경 변수로 참조

| 항목 | 내용 |
|------|------|
| 분류 | API 및 운영 관리 > 보안/권한 |
| 지원 단계 | GA |
| 시연 방식 | OpenShift AI Dashboard UI + CLI 확인 |
| 예상 소요 | 약 7분 |

## 기능 설명

워크벤치를 만들 때 프로젝트 안에 이미 존재하는 Secret을 골라 환경 변수로 연결합니다. External Secrets Operator나 Vault처럼 외부 도구가 관리하는 Secret을 그대로 참조하므로, 사용자가 값을 Dashboard에 다시 입력할 필요가 없습니다.

## 전달 메시지

- 자격 증명의 원본은 Vault/External Secrets에 두고, 워크벤치는 참조만 합니다. 값이 복제되지 않습니다.
- 데이터 사이언티스트는 값을 보지 않고도 키 이름만으로 연결할 수 있습니다.
- 원본 Secret이 로테이션되면 워크벤치 재시작만으로 새 값이 반영됩니다.

## 사전 준비

- 데모 프로젝트 `security-demo` (README의 공통 사전 준비 참고)
- 외부 도구가 만든 것으로 가정할 Secret 1개

harness 명령: `scenario2-prep`(Secret 생성) → `scenario2-verify`(워크벤치 생성 후) → `scenario2-stop`

External Secrets/Vault가 없는 환경에서는 아래처럼 CLI로 Secret을 미리 만들어 "외부에서 관리되는 Secret"을 대신합니다. 값은 데모용 더미 값을 쓰세요. `scenario2-prep`이 같은 작업을 합니다.

```
oc create secret generic external-db-credentials -n security-demo --from-literal=DB_HOST=db.example.internal --from-literal=DB_USER=demo --from-literal=DB_PASSWORD=<더미값>
oc label secret external-db-credentials -n security-demo app.kubernetes.io/managed-by=external-secrets
```

> External Secrets Operator가 설치된 환경이라면 `ExternalSecret` 리소스로 생성한 Secret을 쓰는 편이 더 설득력 있습니다.

## 시연 절차

### 1) 프로젝트 내 외부 도구로 생성된 Secret 존재 확인

값을 노출하지 않고 키 이름만 보여줍니다. `describe`는 키와 바이트 크기만 출력합니다.

```
oc get secret external-db-credentials -n security-demo --show-labels
oc describe secret external-db-credentials -n security-demo
```

> 설명 포인트: 이 Secret은 Dashboard가 만든 것이 아니라 플랫폼 팀의 시크릿 관리 체계가 만든 것입니다.

### 2) 워크벤치 생성 UI에서 `Existing secret` 선택

1. Dashboard에서 `security-demo` 프로젝트 → **Workbenches** → **Create workbench**.
2. 이름(예: `secret-demo-wb`), 이미지, 크기를 선택합니다.
3. **Environment variables** 섹션에서 변수를 추가하고 유형으로 **Existing secret**을 선택합니다.
4. 목록에서 `external-db-credentials`를 고릅니다.

### 3) 값 노출 없이 특정 키를 환경 변수로 연결

1. Secret의 키 중 `DB_PASSWORD`를 선택해 환경 변수로 매핑합니다.
2. 화면에 값이 표시되지 않고 키 이름만 보이는 것을 강조합니다.
3. 워크벤치를 생성하고 Running 상태가 될 때까지 기다립니다.

## 결과 확인

### Notebook CR에 값이 아닌 참조가 들어갔는지 확인

```
oc get notebook secret-demo-wb -n security-demo -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}{' => '}{.valueFrom}{'\n'}{end}"
oc get notebook secret-demo-wb -n security-demo -o jsonpath="{.spec.template.spec.containers[0].envFrom}"
```

`DB_PASSWORD` 항목에 평문 값 대신 `secretKeyRef`(Secret 이름과 키)가 나오면 성공입니다.

### 워크벤치 안에서 변수가 주입됐는지 확인

워크벤치의 터미널에서 값을 출력하지 않고 설정 여부만 확인합니다.

```
[ -n "$DB_PASSWORD" ] && echo "DB_PASSWORD is set" || echo "DB_PASSWORD is NOT set"
```

### 새 Secret이 복제 생성되지 않았는지 확인

```
oc get secret -n security-demo
```

워크벤치 생성 전후로 `external-db-credentials`의 사본이 생기지 않았음을 보여줍니다.

## 정리

```
oc delete notebook secret-demo-wb -n security-demo
oc delete secret external-db-credentials -n security-demo
```

워크벤치용 PVC가 남아 있으면 Dashboard의 Cluster storage에서 함께 삭제합니다.

## 리허설 시 확인할 점

- Environment variables 섹션의 유형 표기가 `Existing secret`으로 나오는지
- 키 단위 선택(`secretKeyRef`)인지, Secret 전체 연결(`envFrom`)인지 — 위 확인 명령 두 줄로 구분됩니다
- 목록에 표시되는 Secret의 조건 (특정 라벨이 필요한지, 타입 제한이 있는지)
