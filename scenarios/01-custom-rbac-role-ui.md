# 시나리오 1. 데이터 사이언스 프로젝트 커스텀 RBAC 역할 생성 UI

| 항목 | 내용 |
|------|------|
| 분류 | API 및 운영 관리 > 보안/권한 |
| 지원 단계 | GA |
| 시연 방식 | OpenShift AI Dashboard UI + CLI 확인 |
| 예상 소요 | 약 10분 |
| 확인 환경 | RHOAI 3.5.1 / OpenShift 4.22.16 |

## 기능 설명

CLI나 YAML 작업 없이 Dashboard UI에서 프로젝트 범위의 커스텀 RBAC Role을 만듭니다. `Workbench maintainer` 같은 템플릿에서 시작하거나 기존 Role을 복제할 수 있고, 생성 전에 YAML 프리뷰로 결과를 확인합니다.

## 전달 메시지

- **핵심은 역할이 만들어지는 것이 아니라, 그 역할을 받은 일반 사용자가 허용된 것만 할 수 있다는 점입니다.** 시연은 5)의 일반 사용자 로그인까지 가야 완성됩니다.
- 기본 제공 역할(Admin / Contributor)만으로는 부족했던 세분화된 권한을 프로젝트 관리자가 직접 설계할 수 있습니다.
- YAML을 몰라도 폼으로 작성하고, YAML을 아는 사람은 프리뷰로 검증할 수 있습니다.
- 결과물은 표준 Kubernetes `Role`이므로 기존 감사·GitOps 체계와 그대로 호환됩니다.

## 사전 준비

### 프로젝트

데모 프로젝트 `security-demo`를 만듭니다.

```
./harness/harness.sh scenario1-prep
```

### 계정

역할을 만드는 관리자 계정 1개와, 기능 제한을 보여줄 일반 사용자 계정 3개가 필요합니다.

| 계정 | 부여할 역할 | 용도 |
|------|-------------|------|
| `admin` | — (클러스터 관리자) | 역할 생성과 부여 |
| `wb-maintainer` | Workbench maintainer | 워크벤치는 관리하지만 그 외는 못 하는 사용자 |
| `wb-reader` | Workbench reader | 조회만 가능한 사용자 |
| `wb-none` | 없음 | 역할이 없으면 프로젝트가 보이지 않음을 보여주는 대조군 |

계정 비밀번호는 이 문서에 적지 않습니다 (저장소가 공개되어 있음). 환경별 접속 정보를 관리하는 곳에 따로 기록하세요.

> 일반 사용자 계정은 harness가 만들지 않습니다. 클러스터의 identity provider(이 환경에서는 `openshift-config`의 `htpass-secret`)에 직접 추가해야 하며, 기존 `admin` 항목은 유지해야 합니다. 추가 후 OAuth 파드가 재시작되므로(약 1~2분) 시연 전에 미리 해 두세요.

### 시연 전 점검

프로젝트에 커스텀 역할이 없는 상태인지 확인합니다.

```
oc get role -n security-demo
```

Dashboard 기능 플래그 `roleManagement`, `projectRBAC`가 모두 `true`인지 확인합니다.

```
./harness/harness.sh check
```

## 시연 절차

| 단계 | 계정 | 내용 |
|------|------|------|
| 1) | `admin` | Project Settings → Roles 메뉴 이동 |
| 2) | `admin` | Role 생성 위저드 진입, 템플릿 선택 |
| 3) | `admin` | 폼으로 권한 선택 → YAML 프리뷰 → 생성 |
| 4) | `admin` | 일반 사용자에게 역할 부여 |
| 5) | 일반 사용자 3명 | 로그인해 기능 제한 확인 |

### 1) Project Settings → Roles 메뉴 이동

1. Dashboard 좌측 메뉴 **Projects** → `Security Demo` 프로젝트를 엽니다.
2. 프로젝트의 **Settings** 탭으로 이동해 **Roles** 메뉴를 엽니다.
3. 현재 프로젝트에 존재하는 역할 목록을 보여줍니다.

> 설명 포인트: 지금까지는 이 화면 없이 `oc create role` 또는 YAML로만 가능했던 작업입니다.

![Create custom role 화면](images/01-create-custom-role.png)

### 2) Role 생성 위저드 진입

1. 역할 생성 버튼으로 **Create custom role** 화면에 진입합니다.
2. 우측 상단 **Select role template**에서 템플릿(`Workbench maintainer`)을 선택합니다.
3. **Role configuration**에서 역할 이름을 입력합니다. 예: `workbench-maintainer-custom`

![Select a role template 대화상자](images/02-select-role-template.png)

**Workbench management templates** 그룹에서 제공되는 템플릿:

| 템플릿 | 설명 |
|--------|------|
| Workbench maintainer | 워크벤치 컴포넌트의 관리자 역할 |
| Workbench reader | 수정 권한 없이 워크벤치 조회만 가능 |
| Workbench updater | 워크벤치 컴포넌트의 업데이트 담당 역할 |

> 기존 역할을 복제(Duplicate)해서 시작하는 경로도 함께 보여주면 좋습니다.

### 3) 폼 기반 권한 선택 → YAML 프리뷰 → 생성

1. **Form** 보기에서 템플릿이 채워 준 리소스별 권한을 확인하고, 필요하면 조정합니다.
2. 우측 상단 토글을 **YAML (read-only)** 로 바꿔 폼 선택이 `rules`로 어떻게 변환됐는지 보여줍니다.
3. 역할을 생성하고, 목록에 새 역할이 나타나는 것을 확인합니다.
4. 같은 방법으로 `Workbench reader` 템플릿에서 두 번째 역할을 만듭니다. 제한이 가장 뚜렷하게 드러나는 대조군입니다.

### 4) 일반 사용자에게 역할 부여

만든 역할을 일반 사용자에게 연결합니다. 프로젝트의 권한 관리 화면에서 할당하거나, harness로 한 번에 처리합니다.

```
./harness/harness.sh scenario1-bind
```

| 계정 | 연결되는 역할 |
|------|---------------|
| `wb-maintainer` | `workbench-maintainer` |
| `wb-reader` | `workbench-reader` |
| `wb-none` | 연결하지 않음 |

UI에서 역할을 만들지 않았다면 [harness/manifests/](../harness/manifests/)의 매니페스트로 대신 생성합니다.

### 5) 일반 사용자로 로그인해 기능 제한 확인

#### 권한 표로 전체 그림 보여주기

API 서버 기준으로 각 사용자가 할 수 있는 일을 표로 출력합니다.

```
./harness/harness.sh scenario1-verify
```

| 동작 | `wb-maintainer` | `wb-reader` | `wb-none` |
|------|:---:|:---:|:---:|
| 프로젝트 보기 | yes | yes | no |
| 워크벤치 조회 | yes | yes | no |
| 워크벤치 생성 | yes | **no** | no |
| 워크벤치 삭제 | yes | **no** | no |
| Secret 읽기 | yes | **no** | no |
| 모델 배포 | **no** | no | no |
| 권한 부여(RoleBinding 생성) | **no** | no | no |

이어서 브라우저 시크릿 창에서 각 계정으로 Dashboard에 로그인해, 같은 차이를 화면으로 보여줍니다.

#### `wb-none` — 프로젝트가 보이지 않음

**Projects** 목록이 비어 있습니다. `Security Demo` 프로젝트가 존재한다는 사실 자체가 보이지 않습니다.

![wb-none의 Projects 화면 — 프로젝트 목록이 비어 있음](images/05-none-no-projects.png)

우측 상단의 **Start basic workbench** 버튼은 프로젝트 역할과 무관한 공용 기능이라 그대로 보입니다 (아래 "제한 범위" 참고).

#### `wb-reader` — 보이지만 만들 수 없음

프로젝트와 탭은 모두 보이지만, Overview의 **Create a workbench** 버튼이 비활성화되어 있습니다. 조회 권한만 있고 생성 권한이 없기 때문입니다. Pipelines 카드에도 관리자에게 권한을 요청하라는 안내가 표시됩니다.

![wb-reader의 프로젝트 Overview — Create a workbench 버튼 비활성화](images/04-reader-create-workbench-disabled.png)

#### `wb-maintainer` — 워크벤치는 되지만 모델 배포는 안 됨

워크벤치는 만들고 지울 수 있습니다. 하지만 **Deployments** 탭을 열면 내용 대신 **Access permissions needed** 안내가 표시됩니다. 역할에 모델 서빙 권한이 없기 때문입니다.

![wb-maintainer의 Deployments 탭 — Access permissions needed](images/03-maintainer-deployments-denied.png)

> 설명 포인트: admin은 역할을 설계만 했고, 실제 제한은 Kubernetes RBAC가 강제합니다. Dashboard를 우회해 `oc`로 접근해도 결과는 같습니다.

#### 제한 범위

커스텀 역할이 제한하는 범위는 `security-demo` 프로젝트 안입니다. 역할이 없는 `wb-none`도 다른 경로로는 워크벤치를 만들 수 있습니다.

- 공용 네임스페이스 `rhods-notebooks`에 뜨는 기본 워크벤치 (Start basic workbench)
- OpenShift 기본 설정(`self-provisioners`)으로 자기 프로젝트를 새로 만들어 그 안에서 생성

둘 다 이 기능과 별개의 클러스터 기본 정책입니다. 시연에서는 "`security-demo`가 보이지 않고 그 안에서는 아무것도 못 한다"는 점만 보여주세요.

## 결과 확인 (CLI)

UI에서 만든 역할과 부여 결과가 표준 Kubernetes 리소스로 생성됐는지 확인합니다.

```
oc get role -n security-demo -l opendatahub.io/dashboard=true
oc get rolebinding -n security-demo -l opendatahub.io/dashboard=true -o wide
```

개별 권한은 `oc auth can-i`로 직접 확인할 수 있습니다.

```
oc auth can-i delete notebooks.kubeflow.org -n security-demo --as=wb-reader
```

> 참고: 폼에 입력한 이름은 `openshift.io/display-name` 어노테이션에 저장되고, 실제 리소스 이름(`metadata.name`)은 다를 수 있습니다. `Workbench maintainer` 템플릿으로 `workbench-maintainer-custom`을 만들었을 때 리소스 이름은 `workbench-maintainer`였습니다. harness는 두 이름 모두로 역할을 찾습니다.

## 정리

커스텀 역할 2개와 RoleBinding을 삭제합니다.

```
./harness/harness.sh scenario1-stop
```

일반 사용자 계정은 identity provider에서 직접 제거해야 합니다.
