# OpenShift AI 3.5 GA 기능 목록 (보안 관련)

이 저장소의 시나리오 1~6이 다루는 OpenShift AI 3.5 GA 기능 목록입니다. 기능명, 설명, 데모 흐름은 제공받은 기능 목록을 그대로 옮겼고, 각 기능의 시연 문서와 이 저장소에서의 확인 상태를 덧붙였습니다.

시나리오 7~10은 이 기능들을 운영에 적용하는 확장 시나리오로, GA 기능 목록에는 포함하지 않았습니다.

## 요약

| # | 대분류 | 소분류 | 기능명 | 지원 단계 | 시연 문서 |
|---|--------|--------|--------|:---:|-----------|
| 1 | API 및 운영 관리 | 보안/권한 | 데이터 사이언스 프로젝트 커스텀 RBAC 역할 생성 UI | GA | [시나리오 1](scenarios/01-custom-rbac-role-ui.md) |
| 2 | API 및 운영 관리 | 보안/권한 | 기존 Kubernetes Secret을 워크벤치 환경 변수로 참조 | GA | [시나리오 2](scenarios/02-existing-secret-workbench-env.md) |
| 3 | API 및 운영 관리 | 보안/권한 | DataScienceCluster API를 통한 OAuth Proxy 리소스 지정 | GA | [시나리오 3](scenarios/03-dsc-oauth-proxy-resources.md) |
| 4 | 평가 및 보안 | 보안/자산 | Red Hat 검증 모델 적대적 취약점 스캐닝 | GA | [시나리오 4](scenarios/04-validated-model-garak-scanning.md) |
| 5 | 평가 및 보안 | 보안/자산 | Automated Red Teaming (자동화된 레드티밍) | GA | [시나리오 5](scenarios/05-automated-red-teaming.md) |
| 6 | 평가 및 보안 | 보안/자산 | Red Hat AI 모델 카탈로그 Safety & Security 탭 | GA | [시나리오 6](scenarios/06-model-catalog-safety-security-tab.md) |

## API 및 운영 관리 > 보안/권한

### 1. 데이터 사이언스 프로젝트 커스텀 RBAC 역할 생성 UI

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | CLI/YAML 작업 없이 UI 상에서 Workbench maintainer 등 템플릿 기반 커스텀 RBAC Role 작성 및 복제 |
| 데모 시나리오 | 1) Project Settings → Roles 메뉴 이동 → 2) Role 생성 위저드 진입 → 3) 폼 기반으로 권한 선택 후 YAML 프리뷰 확인 및 역할 생성 |
| 시연 문서 | [scenarios/01-custom-rbac-role-ui.md](scenarios/01-custom-rbac-role-ui.md) |
| 확인 상태 | 확인됨 — 역할 생성, 일반 사용자 3명에게 부여, 사용자별 기능 제한 화면까지 |

### 2. 기존 Kubernetes Secret을 워크벤치 환경 변수로 참조

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | 워크벤치 생성 시 External Secrets/Vault로 관리되는 프로젝트 내부의 기존 Secret을 환경변수로 연동 |
| 데모 시나리오 | 1) 프로젝트 내 외부 도구로 생성된 Secret 존재 확인 → 2) 워크벤치 생성 UI에서 'Existing secret' 선택 → 3) 값 노출 없이 특정 키를 환경변수로 연결 |
| 시연 문서 | [scenarios/02-existing-secret-workbench-env.md](scenarios/02-existing-secret-workbench-env.md) |
| 확인 상태 | 확인됨 — Existing secret 화면, 키별 `secretKeyRef` 참조, Secret 사본 없음, 워크벤치 안 환경 변수 주입. 화면에서는 Secret 단위로 선택(키를 골라내는 단계 없음) |

### 3. DataScienceCluster API를 통한 OAuth Proxy 리소스 지정

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | `spec.components.kserve.oauthProxy.resources` 설정을 통해 Unmanaged 전환 없이 OAuth sidecar 리소스 제어 |
| 데모 시나리오 | 1) DataScienceCluster CR 편집 → 2) oauthProxy CPU/Memory request 및 limit 수정 → 3) Unmanaged 변경 없이 reconciled 상태 유지하며 파드 리소스 적용 확인 |
| 시연 문서 | [scenarios/03-dsc-oauth-proxy-resources.md](scenarios/03-dsc-oauth-proxy-resources.md) |
| 확인 상태 | 확인됨 — DSC 패치, `Managed` 유지, ConfigMap 반영(약 20초), 모델 파드 자동 교체로 새 리소스 적용(약 1분), 원복 |

## 평가 및 보안 > 보안/자산

### 4. Red Hat 검증 모델 적대적 취약점 스캐닝

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | garak 스캐너 기반 적대적 공격 취약성 스캐닝을 검증 파이프라인에 통합하고 스코어 공개 |
| 데모 시나리오 | 1) Red Hat AI 모델 카탈로그 접속 → 2) 모델 스펙 내 garak 스캔 결과 확인 → 3) Prompt Injection 등 보안 항목 정량 점수 검토 |
| 시연 문서 | [scenarios/04-validated-model-garak-scanning.md](scenarios/04-validated-model-garak-scanning.md) |
| 확인 상태 | 확인됨 — AI hub → Models → 모델 상세 → Safety and security insights 탭에 garak 점수(백분율) 표시, API 값과 일치(25개 모델에 점수) |

### 5. Automated Red Teaming (자동화된 레드티밍)

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | garak 기반 멀티랭귀지/멀티클래스 안전성 평가를 공극(Air-gapped) 및 KFP 파이프라인 지원 |
| 데모 시나리오 | 1) Automated Red Teaming 파이프라인 실행 → 2) 다국어 번역 및 적대적 프롬프트 자동 주입 → 3) 안전성 침해 요인 리포트 생성 |
| 시연 문서 | [scenarios/05-automated-red-teaming.md](scenarios/05-automated-red-teaming.md) |
| 확인 상태 | 확인됨 — 파이프라인 실행(Dashboard Runs 화면), 공격 프롬프트 합성·단계적 주입, 리포트 생성. 다국어 번역 평가는 [시나리오 11](scenarios/11-multilingual-safety.md)에서 확인(중국어만 지원). 폐쇄망 동작과 Dashboard에서의 제출은 확인하지 않음 |

### 6. Red Hat AI 모델 카탈로그 Safety & Security 탭

| 항목 | 내용 |
|------|------|
| 지원 단계 | GA |
| 설명 / 주요 내용 | 모델 카탈로그 UI 내 전용 탭에서 프롬프트 주입, 탈옥, 유해 콘텐츠 방어 스캔 결과 표시 |
| 데모 시나리오 | 1) 모델 카탈로그 진입 → 2) 특정 모델 선택 후 'Safety and Security Insights' 탭 클릭 → 3) 카테고리별 보안 스캔 스코어 시각적 확인 |
| 시연 문서 | [scenarios/06-model-catalog-safety-security-tab.md](scenarios/06-model-catalog-safety-security-tab.md) |
| 확인 상태 | 확인됨 — Safety and security insights 탭에 카테고리별 점수(백분율) 표시, API 값과 일치. 통과/실패 표시는 없음 |

## 확인 환경

확인 상태는 RHOAI 3.5.1 / OpenShift 4.22.16 클러스터에서 이 저장소의 harness로 확인한 결과입니다. 시연 절차와 명령은 각 시연 문서에 있습니다.
