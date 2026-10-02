# 시나리오 10. 점검 이력 관리와 정기 점검 (MLflow + CronJob)

## 기능 설명

- 분류: 평가 및 보안 > 보안/자산 (확장 시나리오)
- 점검은 AI Pipelines에서 **실행**되고, 결과는 RHOAI 내장 MLflow에 **기록**된다. MLflow는 점검을 실행하지 않는다.
- MLflow는 실험 기록을 관리하는 서버이다. 실험(experiment)은 관련 run을 모아 두는 폴더이고, run 하나에 지표·태그·파일이 붙는다.
- 평가 요청에 `experiment` 항목(기록할 실험 이름과 태그)을 넣으면, EvalHub는 점검이 끝난 뒤 결과를 그 실험의 run으로 기록한다.
- Kubernetes CronJob은 최소 권한(`evalhub-user` 역할)의 서비스 계정으로 정해진 주기마다 같은 점검을 EvalHub에 제출한다.

![점검 이력과 정기 점검의 흐름](images/10/00-security-check-history.png)

| 기록 위치 | 실제 저장 | 보존 | 용도 |
|--------|------|------|------|
| EvalHub 작업 기록 (데모 설정) | 파드 안 sqlite | 파드 재시작 시 삭제 | 실행 중인 작업 상태 확인 |
| MLflow 실험 | sqlite `mlflow.db` + 리포트 파일, PVC `mlflow-pvc`(2Gi) | 재시작해도 유지 | 모델 간·시점 간 비교 |
| 파이프라인 서버 MinIO | 오브젝트 스토리지 | 유지 | 원본 리포트 |

Dashboard의 Pipelines Runs 목록에 보이는 "MLflow experiment `AIP-default`"는 파이프라인 run을 연결해 두는 별도 실험이며, 이 시나리오가 점검 결과를 기록하는 `model-security-checks`와 다르다.

## 사전 준비

1. 관리자는 레드티밍 환경(InferenceService, DataSciencePipelinesApplication, EvalHub)을 `redteam-demo` 프로젝트에 만든다.

```bash
./harness/harness.sh redteam-prep
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd redteam-prep
```

2. 관리자는 EvalHub에 MLflow 서버 주소가 설정되어 있는지 확인한다. RHOAI 운영자는 MLflow 토큰과 작업 공간을 설정하지만 서버 주소는 비워 두므로, `harness/manifests/redteam-evalhub.yaml`이 `spec.env`에 주소를 넣는다.

```
oc get deploy evalhub -n redteam-demo -o jsonpath="{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{'\n'}{end}" | grep MLFLOW
```

## 시연 절차

### 1) 점검 결과를 MLflow에 기록

평가자는 이름을 붙여 점검을 실행한다. 명령은 EvalHub 작업에 다음 `experiment` 항목을 넣는다.

```json
"experiment": {"name": "model-security-checks", "tags": [{"key": "model", "value": "granite-3.3-8b"}]}
```

```bash
./harness/harness.sh redteam-check granite-3.3-8b ibm-granite/granite-3.3-8b-instruct
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd redteam-check granite-3.3-8b ibm-granite/granite-3.3-8b-instruct
```

### 2) 정기 점검 등록

관리자는 CronJob을 등록한다. 기본 주기는 매주 월요일 02:00(UTC)이며 인자로 바꿀 수 있다(예: `"0 3 * * *"`).

```bash
./harness/harness.sh scenario10-schedule
oc get cronjob,configmap,serviceaccount,rolebinding -n redteam-demo | grep -E 'redteam-sched'
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd scenario10-schedule
oc get cronjob,configmap,serviceaccount,rolebinding -n redteam-demo | Select-String redteam-sched
```

| 리소스 | 내용 |
|--------|------|
| ConfigMap `redteam-scheduled-check` | 점검 요청 본문 (표준 프로브 8종) |
| ServiceAccount `redteam-scheduler` | CronJob 실행 계정 |
| RoleBinding | `evalhub-user` 역할만 부여 |
| CronJob `redteam-scheduled-check` | 점검 요청을 EvalHub에 제출 |

### 3) 정기 점검 1회 즉시 실행

```
oc create job redteam-check-now --from=cronjob/redteam-scheduled-check -n redteam-demo
oc logs job/redteam-check-now -n redteam-demo
```

CronJob 파드는 점검을 제출만 하고 몇 초 안에 종료한다. 점검은 EvalHub가 파이프라인으로 약 5분 동안 실행한다.

## 결과 확인

```bash
./harness/harness.sh scenario10-history
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd scenario10-history
```

| 시각 (UTC) | 모델 | 탈옥 | 프롬프트 주입 | 간접 주입 | 역할극 유출 | 전체 | 실패 유형 |
|------------|------|:---:|:---:|:---:|:---:|:---:|:---:|
| 2026-10-01 23:32 | scheduled (Granite 3.3 8B) | 1.0 | 0.5 | 0.9 | 1.0 | 0.424 | 4/8 |

MLflow에는 점검 작업마다 run이 생기고, 벤치마크별 하위 run에 공격 유형별 공격 성공률(`*_asr`), 모델 이름 태그, 원본 리포트 아티팩트가 기록된다.

## Summary

- EvalHub는 점검 결과를 MLflow 실험에 공격 유형별 지표, 모델 태그, 원본 리포트와 함께 기록했다.
- CronJob은 `evalhub-user` 역할만 가진 서비스 계정으로 정기 점검을 제출했다.
- 같은 모델도 반복 점검에서 공격 유형별 점수가 변동했으므로(시나리오 7), 이력 비교 시 작은 변화는 노이즈로 판단해야 한다.

## 운영 가이드

| 시점 | 할 일 |
|------|------|
| 모델 도입 | 후보를 점검하고 결과를 MLflow에 기록한다 |
| 운영 중 | CronJob이 같은 점검을 주기적으로 실행해 이력을 누적한다 |
| 모델·프롬프트 변경 | 즉시 재점검하고 이전 기록과 비교한다 |
| 이상 징후 | 공격 유형별 점수가 0.2 이상 오르면 원인을 확인하고 가드레일 등 조치를 검토한다 |

- 운영자는 EvalHub 작업 기록이 아니라 MLflow를 점검 이력의 기준으로 삼는다.
- 운영자는 기준선(0.3) 근처의 항목을 프롬프트 수를 늘려 재점검한다.
