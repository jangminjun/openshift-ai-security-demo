# OpenShift AI 보안 데모

OpenShift AI(RHOAI)의 보안 관련 GA 기능 6가지를 시연하는 데모 시나리오 모음입니다. 두 영역으로 나뉘며, 기능을 실제 점검 업무와 운영에 적용하는 확장 시나리오 4개가 더 있습니다.

- **API 및 운영 관리 > 보안/권한** (시나리오 1~3): 누가 무엇을 할 수 있는지, 자격 증명과 운영 설정을 어떻게 다루는지
- **평가 및 보안 > 보안/자산** (시나리오 4~6): 모델 자체가 공격에 얼마나 안전한지

GA 기능(시나리오 1~6)만 따로 정리한 목록은 [rhoai-3.5-ga-features.md](rhoai-3.5-ga-features.md)에 있습니다.

## 기능 요약

### API 및 운영 관리 > 보안/권한

| # | 기능명 | 무엇이 달라지나 | 시연 방식 | 시나리오 |
|---|--------|-----------------|-----------|----------|
| 1 | 데이터 사이언스 프로젝트 커스텀 RBAC 역할 생성 UI | CLI/YAML 없이 UI에서 템플릿 기반 커스텀 Role을 작성·복제 | Dashboard UI + CLI 확인 | [01-custom-rbac-role-ui.md](scenarios/01-custom-rbac-role-ui.md) |
| 2 | 기존 Kubernetes Secret을 워크벤치 환경 변수로 참조 | External Secrets/Vault가 만든 기존 Secret을 값 노출 없이 워크벤치에 연결 | Dashboard UI + CLI 확인 | [02-existing-secret-workbench-env.md](scenarios/02-existing-secret-workbench-env.md) |
| 3 | DataScienceCluster API를 통한 OAuth Proxy 리소스 지정 | `Unmanaged` 전환 없이 OAuth sidecar의 CPU/Memory를 제어 | CLI (DSC CR 편집) | [03-dsc-oauth-proxy-resources.md](scenarios/03-dsc-oauth-proxy-resources.md) |

### 평가 및 보안 > 보안/자산

| # | 기능명 | 무엇이 달라지나 | 시연 방식 | 시나리오 |
|---|--------|-----------------|-----------|----------|
| 4 | Red Hat 검증 모델 적대적 취약점 스캐닝 | garak 스캔이 검증 파이프라인에 통합되고 점수가 공개됨 | 모델 카탈로그 UI + CLI 확인 | [04-validated-model-garak-scanning.md](scenarios/04-validated-model-garak-scanning.md) |
| 5 | Automated Red Teaming (자동화된 레드티밍) | 내 모델에 garak 기반 안전성 평가를 파이프라인으로 자동 실행 | 파이프라인 실행 | [05-automated-red-teaming.md](scenarios/05-automated-red-teaming.md) |
| 6 | Red Hat AI 모델 카탈로그 Safety & Security 탭 | 카탈로그 전용 탭에서 카테고리별 보안 스캔 점수를 표시 | 모델 카탈로그 UI | [06-model-catalog-safety-security-tab.md](scenarios/06-model-catalog-safety-security-tab.md) |

### 확장 시나리오

| # | 시나리오 | 무엇을 보여주나 | 시연 방식 | 문서 |
|---|----------|-----------------|-----------|------|
| 7 | 모델 보안 점검: 배포해도 되는 모델인가 | 후보 모델들을 같은 시험지로 점검해 취약한 모델을 골라내는 절차 (시나리오 5 기능 활용) | CLI + 리포트 | [07-model-security-check.md](scenarios/07-model-security-check.md) |
| 8 | 용도별 점검 프로필 | 코딩 어시스턴트 / 고객 상담 챗봇 / RAG·에이전트에 맞춘 garak 시험지와 오탐 거르기 | CLI + 리포트 | [08-use-case-profiles.md](scenarios/08-use-case-profiles.md) |
| 9 | 가드레일 적용 전후 비교 | TrustyAI Guardrails로 방어막을 씌우고 같은 점검으로 개선 효과를 숫자로 증명 | CLI + 리포트 | [09-guardrails-before-after.md](scenarios/09-guardrails-before-after.md) |
| 10 | 점검 이력 관리와 정기 점검 | 점검 결과를 MLflow에 영구 기록하고 CronJob으로 주기적 재점검 | CLI + MLflow | [10-security-check-history.md](scenarios/10-security-check-history.md) |

모든 기능의 지원 단계는 GA입니다.

## 기능별 핵심 내용

### 1. 커스텀 RBAC 역할 생성 UI

- **대상 사용자**: 프로젝트 관리자
- **내용**: `Workbench maintainer` 같은 템플릿을 기반으로 프로젝트 범위의 커스텀 Role을 폼으로 작성하거나 기존 Role을 복제합니다.
- **데모 흐름**: Project Settings → Roles 이동 → Role 생성 위저드 진입 → 폼에서 권한 선택 → YAML 프리뷰 확인 → 역할 생성 → 일반 사용자에게 역할 부여 → 일반 사용자로 로그인해 기능 제한 확인

### 2. 기존 Secret을 워크벤치 환경 변수로 참조

- **대상 사용자**: 데이터 사이언티스트, 플랫폼 관리자
- **내용**: 워크벤치 생성 시 프로젝트 안에 이미 존재하는 Secret(External Secrets, Vault 등 외부 도구가 관리)을 환경 변수로 연동합니다. 사용자가 값을 직접 입력하거나 볼 필요가 없습니다.
- **데모 흐름**: 외부 도구로 생성된 Secret 존재 확인 → 워크벤치 생성 UI에서 `Existing secret` 선택 → 특정 키를 환경 변수로 연결

### 3. DSC API를 통한 OAuth Proxy 리소스 지정

- **대상 사용자**: 클러스터/플랫폼 관리자
- **내용**: `spec.components.kserve.oauthProxy.resources`에 request/limit을 지정해 OAuth sidecar 리소스를 제어합니다. 컴포넌트를 `Unmanaged`로 바꾸지 않으므로 오퍼레이터의 reconcile이 유지됩니다.
- **데모 흐름**: DataScienceCluster CR 편집 → oauthProxy CPU/Memory request·limit 수정 → reconciled 상태 유지 확인 → 파드에 리소스 적용 확인

### 4. Red Hat 검증 모델 적대적 취약점 스캐닝

- **대상 사용자**: 모델을 선택하는 AI 엔지니어, 보안 담당자
- **내용**: Red Hat의 모델 검증 파이프라인에 garak 스캐너 기반 적대적 공격 취약성 스캐닝이 통합되어 있고, 그 점수가 모델 카탈로그에 공개됩니다.
- **데모 흐름**: Red Hat AI 모델 카탈로그 접속 → 모델 스펙 내 garak 스캔 결과 확인 → Prompt Injection 등 보안 항목 정량 점수 검토

### 5. Automated Red Teaming

- **대상 사용자**: 모델을 배포하는 AI 엔지니어, 보안 담당자
- **내용**: garak 기반 멀티랭귀지/멀티클래스 안전성 평가를 폐쇄망(air-gapped)과 KFP 파이프라인에서 실행합니다. RHOAI 3.5.1에서는 TrustyAI EvalHub의 `garak` / `garak-kfp` 프로바이더로 제공됩니다. 공격 프롬프트를 자동 합성하고, 변형·번역해 주입한 뒤 리포트를 만듭니다.
- **데모 흐름**: Automated Red Teaming 파이프라인 실행 → 다국어 번역 및 적대적 프롬프트 자동 주입 → 안전성 침해 요인 리포트 생성

### 6. 모델 카탈로그 Safety & Security 탭

- **대상 사용자**: 모델을 선택하는 AI 엔지니어, 보안 담당자
- **내용**: 모델 카탈로그 UI의 전용 탭에서 프롬프트 주입, 탈옥, 유해 콘텐츠 방어 스캔 결과를 카테고리별로 표시합니다.
- **데모 흐름**: 모델 카탈로그 진입 → 모델 선택 후 `Safety and Security Insights` 탭 클릭 → 카테고리별 보안 스캔 스코어 확인

### 7. 모델 보안 점검 (확장)

- **대상 사용자**: 모델 도입을 결정하는 담당자, 보안 담당자 (보안 전문가가 아니어도 됨)
- **내용**: 판정 모델 없이 채점되는 표준 프로브 8종으로 후보 모델을 같은 조건에서 점검하고, 공격 유형별 공격 성공률을 나란히 비교해 배포 여부를 판정합니다.
- **데모 흐름**: 점검 기준 정하기 → 후보 모델 교체 배포 → 같은 조건으로 스캔 → 비교·판정 → 조치·재점검 설명

### 8. 용도별 점검 프로필 (확장)

- **내용**: garak의 다양한 프로브(패키지 환각, 시스템 프롬프트 유출, 문서 속 숨은 지시, XSS 등)를 서비스 용도별 시험지로 묶어 점검하고, 실제 응답을 보며 오탐을 걸러냅니다.
- **데모 흐름**: 용도별 시험지 소개 → 세 프로필 동시 점검 → 결과 비교 → 실제 응답으로 오탐 확인 → 용도별 조치

### 9. 가드레일 적용 전후 비교 (확장, OpenShift AI 연동)

- **내용**: TrustyAI Guardrails Orchestrator와 CPU에서 도는 탐지 모델 2개(프롬프트 주입, 유해 표현)를 대상 모델 앞에 두고, 시나리오 7과 같은 점검을 다시 돌려 전후를 비교합니다.
- **데모 흐름**: 가드레일 구성 → 정상 질문·공격 직접 비교 → 가드레일 경유 점검 → 전후 비교표

### 10. 점검 이력 관리와 정기 점검 (확장, OpenShift 연동)

- **내용**: EvalHub를 RHOAI 내장 MLflow에 연결해 점검 결과를 영구 기록하고, Kubernetes CronJob이 최소 권한 서비스 계정으로 정기 재점검을 제출합니다.
- **데모 흐름**: MLflow 기록 확인 → 정기 점검 등록 → 즉시 1회 실행 → 이력 조회

## 권장 시연 순서

- **1 → 2 → 3**: 1번에서 만든 프로젝트를 2번에서 그대로 쓰고, 3번은 클러스터 관리자 관점으로 전환합니다.
- **6 → 4 → 5 → 7**: 6번에서 카탈로그 탭을 먼저 보여주고, 4번에서 그 점수가 검증 파이프라인에서 나온다는 점과 모델 간 비교를 다룬 뒤, 5번에서 같은 스캔을 내 모델에 직접 돌립니다. 7~10번은 그 기능을 운영에 적용하는 확장 시나리오입니다. 7(후보 비교) → 8(용도별 심화) → 9(조치: 가드레일) → 10(정기 점검) 순서로 이어집니다. 4번과 6번은 같은 데이터를 쓰므로 시간이 부족하면 하나로 합쳐도 됩니다.

## 공통 사전 준비

- OpenShift AI가 설치된 클러스터와 `cluster-admin` 계정
- `oc` CLI와 bash (Windows에서는 Git Bash). 시나리오 4~6의 명령은 `curl`과 `jq`도 사용합니다.

사전 준비·검증·정리는 [harness/harness.sh](harness/harness.sh)로 실행합니다. `oc`가 로그인된 클러스터에 그대로 적용되므로, 샌드박스가 바뀌면 다시 로그인한 뒤 같은 명령을 실행하면 됩니다. 모든 prep/stop 명령은 여러 번 실행해도 안전합니다.

### 새 클러스터에서 시작하기

```bash
cd harness
cp local.env.example local.env   # OCP_API_URL / OCP_USER / OCP_PASSWORD 입력 (gitignore 대상)
./harness.sh login               # 이미 oc login 했다면 생략
./harness.sh check               # RHOAI 버전, DSC, Dashboard 기능 플래그 사전 점검
./harness.sh prep-all            # 시나리오 1~3 사전 준비
```

시나리오 4와 6은 사전 준비가 필요 없습니다. 시나리오 5는 별도 프로젝트에 모델·파이프라인 서버·EvalHub를 만들어야 하고 GPU를 사용하므로 `prep-all`에 포함하지 않았습니다.

```bash
./harness.sh scenario5-prep                      # 모델, 파이프라인 서버, EvalHub 준비 (첫 실행 약 10분)
./harness.sh scenario5-run intents garak-kfp     # 레드티밍 파이프라인 실행 (약 4분)
./harness.sh scenario5-report <job-id>           # 리포트 내려받기
./harness.sh scenario5-stop                      # 정리, GPU 반환
```

### 명령 목록

| 명령 | 하는 일 |
|------|---------|
| `login` | `local.env`의 접속 정보로 `oc login` |
| `check` | 로그인, RHOAI 버전, DSC Ready, `roleManagement`/`projectRBAC` 플래그, `oauthProxy` 필드 점검 |
| `prep-all` / `stop-all` | 시나리오 1~3의 prep / stop 일괄 실행 |
| `destroy-project` | 데모 프로젝트 삭제 |
| `scenario1-prep` / `-bind` / `-verify` / `-stop` | 프로젝트 생성 / 일반 사용자에게 역할 부여 / 사용자별 권한 표 출력 / Role·RoleBinding 삭제 |
| `scenario2-prep` / `-verify` / `-stop` | 프로젝트 + 더미 Secret 생성 / 워크벤치의 Secret 참조 확인 / 워크벤치·Secret 삭제 |
| `scenario3-prep` / `-apply` / `-verify` / `-stop` | 변경 전 상태 확인 / DSC 패치 / 적용 확인 / 원복 |
| `scenario4-models` | garak 스캔 결과가 있는 카탈로그 모델을 전체 공격 성공률 순으로 출력 |
| `scenario4-scores [모델]` | 한 모델의 카테고리별 garak 점수 출력 (시나리오 6에서도 사용) |
| `scenario5-check` | 레드티밍 실행에 필요한 EvalHub·파이프라인 서버·모델 엔드포인트 현황 출력 |
| `scenario5-prep` / `-stop` | `redteam-demo` 프로젝트에 대상 모델·파이프라인 서버·EvalHub·Secret·RBAC 생성 / 프로젝트 삭제 |
| `scenario5-run [벤치마크] [프로바이더]` | garak 스캔 제출 후 완료까지 대기 (기본값 `quick` `garak-kfp`). `REDTEAM_PROBES`로 프로브 지정 가능 |
| `scenario5-status [job-id]` | 스캔 작업 목록, 또는 한 작업의 점수·판정·리포트 위치 |
| `scenario5-report <job-id>` | 파이프라인 모드 작업의 garak 리포트를 `harness/reports/`로 내려받기 |
| `scenario5-cancel <job-id>` | EvalHub 작업 취소와 함께 파이프라인 실행도 중지 (EvalHub 취소만으로는 파이프라인이 계속 돎) |
| `scenario7-scan <이름> <HF 모델 ID>` | 대상 모델을 후보로 교체하고 표준 프로브 8종으로 점검, 결과를 `harness/reports/scenario7.tsv`에 기록 |
| `scenario7-compare` | 기록된 후보들의 프로브별 공격 성공률과 판정을 나란히 출력 |
| `scenario8-scan <이름> <HF 모델 ID>` / `scenario8-compare` | 코딩·챗봇·RAG 프로필 3종 동시 점검 / 프로필별 비교표 |
| `scenario9-prep` / `-demo` / `-scan <이름>` / `-stop` | 탐지 모델 2개와 가드레일 게이트웨이 배포 / 공격 직접 비교 / 가드레일 경유 점검(결과는 `scenario7-compare`에 표시) / 제거 |
| `scenario10-schedule [cron]` / `-trigger` / `-history` / `-unschedule` | 정기 점검 CronJob 등록 / 즉시 1회 실행 / MLflow 이력 조회 / 제거 |

프로젝트 이름, DSC 이름 등 기본값은 [harness/config.env](harness/config.env)에 있고 환경 변수로 덮어쓸 수 있습니다.

## 확인 상태

RHOAI 3.5.1 / OpenShift 4.22.16 기준입니다.

| 시나리오 | 상태 |
|----------|------|
| 1 | 확인됨 — 역할 생성, 역할 부여, 일반 사용자 3명의 제한 화면까지 |
| 2 | 확인됨 — Existing secret 화면, 키별 참조, 워크벤치 안 환경 변수 주입 |
| 3 | 확인됨 — DSC 패치, ConfigMap 반영, 모델 파드 자동 교체, 원복 |
| 4 | 카탈로그 데이터를 API로 확인. 화면은 아직 확인하지 않음 |
| 5 | 확인됨 — 준비, `quick`·`intents` 파이프라인 실행, 리포트 생성까지. 폐쇄망 동작과 Dashboard에서의 제출은 확인하지 않음 |
| 6 | 카탈로그 데이터를 API로 확인. 탭 화면은 아직 확인하지 않음 |
| 7 | 확인됨 — 후보 2개(Qwen 1.5B, Granite 8B) 점검·비교 |
| 8 | 확인됨 — 프로필 3종 점검, 실제 응답으로 오탐 확인 |
| 9 | 확인됨 — 가드레일 구성, 차단 동작, 가드레일 경유 점검 |
| 10 | 확인됨 — MLflow 기록, CronJob 제출, 이력 조회. MLflow 화면 경로는 확인하지 않음 |
