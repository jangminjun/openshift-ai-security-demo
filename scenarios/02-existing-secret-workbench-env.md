# 시나리오 2. 기존 Kubernetes Secret을 워크벤치 환경 변수로 참조

| 항목 | 내용 |
|------|------|
| 분류 | API 및 운영 관리 > 보안/권한 |
| 지원 단계 | GA |
| 시연 방식 | OpenShift AI Dashboard UI + CLI 확인 |
| 예상 소요 | 약 7분 |

## 기능 설명

워크벤치를 만들 때 프로젝트 안에 이미 존재하는 Secret을 골라 환경 변수로 연결합니다. External Secrets Operator나 Vault처럼 외부 도구가 관리하는 Secret을 그대로 참조하므로, 사용자가 값을 Dashboard에 다시 입력할 필요가 없습니다.

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
3. **Environment variables** 섹션에서 변수를 추가하고, **Variable type**을 **Secret**으로 고른 뒤 그 아래 **Existing secret**을 선택합니다.
4. **Search secrets** 목록에서 `external-db-credentials`를 체크합니다.

![Environment variables — Existing secret 선택](images/2/01-existing-secret.png)

화면에서 짚을 점:

| 화면 요소 | 의미 |
|-----------|------|
| Secret 아래 선택지 3개 | **Key / value**(새 값 입력), **Upload**(파일로 입력), **Existing secret**(기존 Secret 참조). 앞의 두 방식은 값을 새로 만들고, Existing secret만 기존 Secret을 가리킴 |
| Existing secret 설명 | "플랫폼 팀이 관리하거나 외부 도구가 만든 Secret을 연결"하는 용도. S3나 DB 접속처럼 재사용할 자격 증명은 **Connections** 섹션을 쓰라고 안내 |
| 목록 항목 `3 keys: DB_HOST, DB_PASSWORD, DB_USER` | 키 이름만 보이고 값은 보이지 않음 |
| 화면 아래 안내 | 환경 변수는 워크벤치가 시작될 때 설정되므로, Secret 값이 바뀌면(예: 비밀번호 교체) **워크벤치를 재시작해야** 새 값이 반영됨 |

### 3) 값 노출 없이 Secret을 환경 변수로 연결

1. 화면에서는 **Secret 단위**로 체크합니다. 그러면 Dashboard가 그 Secret의 키마다 환경 변수를 하나씩 만들고, 각각 "어느 Secret의 어느 키"인지만 참조로 적어 둡니다(`secretKeyRef`). 이 환경에서는 `DB_HOST`, `DB_USER`, `DB_PASSWORD` 3개가 같은 이름의 환경 변수로 연결됐습니다.
2. 화면 어디에도 값이 표시되지 않는 것을 강조합니다.
3. 워크벤치를 생성하고 Running 상태가 될 때까지 기다립니다.

> 설명 포인트: "특정 키를 연결"은 화면에서 키를 하나씩 고른다는 뜻이 아니라, **키 하나하나를 값 대신 참조로 연결한다**는 뜻입니다. 워크벤치 설정에는 값이 전혀 저장되지 않습니다. 화면에서 일부 키만 고르는 기능은 이 환경(RHOAI 3.5.1)에서 확인하지 못했습니다. 일부 키만 넘기려면 그 키만 담은 Secret을 따로 두는 것이 가장 간단합니다.

## 결과 확인

### Notebook CR에 값이 아닌 참조가 들어갔는지 확인

```
oc get notebook secret-demo-wb -n security-demo -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}{' => '}{.valueFrom}{'\n'}{end}"
oc get notebook secret-demo-wb -n security-demo -o jsonpath="{.spec.template.spec.containers[0].envFrom}"
```

평문 값 대신 Secret과 키에 대한 참조가 나오면 성공입니다. 이 환경(RHOAI 3.5.1)에서 실제로 나온 결과입니다.

```
DB_HOST => {"secretKeyRef":{"key":"DB_HOST","name":"external-db-credentials"}}
DB_PASSWORD => {"secretKeyRef":{"key":"DB_PASSWORD","name":"external-db-credentials"}}
DB_USER => {"secretKeyRef":{"key":"DB_USER","name":"external-db-credentials"}}
```

![Notebook CR의 환경 변수 — DB_* 3개가 secretKeyRef로 참조됨](images/2/04-notebook-secretkeyref.png)

다른 변수(`NOTEBOOK_ARGS`, `MLFLOW_TRACKING_URI` 등)는 워크벤치가 원래 갖고 있는 설정이라 참조 칸이 비어 있습니다. `DB_*` 세 줄만 보면 됩니다.

Secret 전체를 한 번에 넣는 `envFrom`은 쓰지 않고(두 번째 명령 결과는 비어 있음), 키마다 `secretKeyRef`로 참조합니다. `./harness/harness.sh scenario2-verify`가 이 확인을 한 번에 합니다.

### 워크벤치 안에서 변수가 주입됐는지 확인

워크벤치(JupyterLab)를 열고 값을 출력하지 않고 설정 여부만 확인합니다. 새 노트북 셀에서:

```python
import os
for v in ["DB_HOST", "DB_USER", "DB_PASSWORD"]:
    print(v, "is set" if os.environ.get(v) else "is NOT set")
```

![워크벤치 노트북에서 환경 변수 확인 — 3개 모두 is set](images/2/02-env-vars-in-workbench.png)

세 변수가 모두 `is set`이면 성공입니다. 터미널(File → New → Terminal)에서는 다음과 같이 확인합니다.

```
for v in DB_HOST DB_USER DB_PASSWORD; do [ -n "$(printenv $v)" ] && echo "$v is set" || echo "$v is NOT set"; done
```

![워크벤치 터미널에서 환경 변수 확인 — 3개 모두 is set](images/2/03-env-vars-in-terminal.png)

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

## 운영 가이드

- 자격 증명의 원본은 Vault/External Secrets에 두고, 워크벤치는 참조만 합니다. 값이 복제되지 않습니다.
- 데이터 사이언티스트는 값을 보지 않고도 키 이름만으로 연결할 수 있습니다.
- 원본 Secret이 로테이션되면 워크벤치 재시작만으로 새 값이 반영됩니다 (화면에도 이 안내가 표시됨).
