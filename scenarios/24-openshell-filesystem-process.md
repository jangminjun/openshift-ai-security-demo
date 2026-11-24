# 시나리오 24. 파일시스템·프로세스 격리

> 상태: 검증 완료(2026-11-24, SNO, OpenShift 4.20.46, OpenShell 0.1.9). RHOAI 3.5에서 OpenShell은 Developer Preview이다.

## 기능 설명

- 분류: 에이전트 보안 > 실행 격리 (Developer Preview)
- OpenShell은 Landlock으로 에이전트가 읽고 쓸 수 있는 경로를 제한한다. 정책에 없는 경로는 접근할 수 없다.
- 에이전트는 root가 아닌 사용자로 실행되며, 모든 Linux capability가 제거된다. OpenShift에서는 네임스페이스의 UID 범위가 실행 사용자를 결정한다.
- 파일시스템·Landlock·프로세스 정책은 샌드박스 시작 시점에 고정된다. 실행 중 정책을 바꿔도 실제 적용 범위는 넓어지지 않는다.

## 사전 준비

- OpenShell 게이트웨이가 설치되어 있어야 한다. 설치 절차는 [시나리오 20. OpenShell 환경 설정](20-openshell-setup.md)을 따른다.
- 정책 파일: [policy-fs.yaml](../harness/openshell/policy-fs.yaml). 읽기 전용 경로는 `/bin`, `/usr`, `/lib`, `/lib64`, `/etc`, `/opt`, `/proc`, `/dev/urandom`이고, 쓰기 가능 경로는 `/sandbox`, `/tmp`, `/dev/null`이다. `landlock.compatibility: hard_requirement`이므로 Landlock을 쓸 수 없으면 샌드박스는 시작하지 않는다.

```
openshell status
openshell sandbox create --name sb-fs \
  --from registry.access.redhat.com/ubi9/python-312:latest \
  --policy harness/openshell/policy-fs.yaml \
  --no-auto-providers --detach -- sleep infinity
```

## 시연 절차

### 1) 실행 사용자 확인

```
openshell sandbox exec -n sb-fs -- id
```

### 2) 허용 경로와 차단 경로 비교

```
openshell sandbox exec -n sb-fs -- sh -c 'echo ok > /sandbox/a.txt && cat /sandbox/a.txt'   # 허용
openshell sandbox exec -n sb-fs -- sh -c 'echo x > /etc/demo.conf'                          # 읽기 전용
openshell sandbox exec -n sb-fs -- sh -c 'cat /proc/1/environ'                              # 다른 프로세스 환경 변수
openshell sandbox exec -n sb-fs -- sh -c 'ls /root /var/lib'                                # 정책에 없는 경로
openshell sandbox exec -n sb-fs -- sh -c 'ls /var/run/secrets/kubernetes.io/serviceaccount' # 서비스 어카운트 토큰
```

### 3) 실행 중 권한 확대 시도

```
sed 's#read_write: \[/sandbox, /tmp, /dev/null\]#read_write: [/sandbox, /tmp, /dev/null, /etc]#' \
  harness/openshell/policy-fs.yaml > /tmp/policy-fs-wide.yaml
openshell policy set sb-fs --policy /tmp/policy-fs-wide.yaml --wait
openshell policy get sb-fs
openshell sandbox exec -n sb-fs -- sh -c 'echo x > /etc/demo.conf && echo WROTE'
```

## 결과 확인

```
openshell policy list sb-fs
openshell logs sb-fs --since 10m | grep -E 'CONFIG'
oc get pod default--sb-fs -n openshell -o jsonpath='automount={.spec.automountServiceAccountToken}{"\n"}'
oc get ns openshell -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
```

| 확인 항목 | 검증 결과 |
|------|------|
| `id` | `uid=1001020000` (네임스페이스 UID 범위, root 아님) |
| `/sandbox` 쓰기 | 성공 (`ok`) |
| `/etc` 쓰기 | `Permission denied` |
| `/proc/1/environ` 읽기 | `Permission denied` |
| `/root`, `/var/lib` 목록 | `Permission denied` |
| 서비스 어카운트 토큰 | 없음 (`automountServiceAccountToken: false`) |
| 실행 중 `/etc` 쓰기 허용으로 변경 | 정책 버전 2가 `Loaded`·`Effective`로 표시되나, `/etc` 쓰기는 계속 `Permission denied` |

## 정리

```
openshell sandbox delete sb-fs
rm -f /tmp/policy-fs-wide.yaml
```

## 운영 가이드

- 실행 중 파일시스템 정책을 바꾸면 CLI와 로그(`CONFIG:LOADED`)는 새 정책이 적용된 것처럼 표시하지만, Landlock 규칙은 시작 시점 그대로 유지된다. 운영자는 표시된 정책과 실제 적용 범위가 다를 수 있음을 알고, 파일시스템 정책을 바꿀 때는 샌드박스를 삭제하고 다시 만든다.
- 운영자는 `landlock.compatibility`를 `hard_requirement`로 둔다. 기본값 `best_effort`는 Landlock을 쓸 수 없을 때 파일 규칙 없이 실행하고 경고만 남긴다.
- RHCOS 4.16~4.18 노드에는 Landlock이 없으므로, 운영자는 샌드박스가 OpenShift 4.19 이상 노드에만 배치되도록 한다.
- 커널 공유에 따른 위험(컨테이너 탈출)까지 막으려면 OpenShift sandboxed containers(Kata)와 함께 쓴다. 차트의 `server.defaultRuntimeClassName` 또는 `--driver-config-json`(게이트웨이에서 `allowDriverConfig` 허용 필요)으로 지정하며, Kata에는 베어메탈 노드나 peer pods가 필요하다.
