# 시나리오 11. 멀티랭귀지 안전성 평가

## 기능 설명

- 분류: 평가 및 보안 > 보안/자산 (확장 시나리오, Automated Red Teaming의 다국어 평가)
- 모델은 영어 요청을 거절하더라도 같은 요청을 다른 언어로 받으면 다르게 반응할 수 있다. 평가자는 garak의 번역 프로브 `multilingual.TranslationIntent`로 이 언어 간 방어 격차를 점검한다.
- 번역 프로브는 `intents` 벤치마크의 한 단계이다. 프로브는 영어로 거절된 공격 프롬프트에 탈옥 템플릿(SPO: DAN, AntiDAN 등)을 씌운 뒤 대상 언어로 번역해 전송하고, 응답을 다시 영어로 번역해 판정한다.
- RHOAI 3.5.1의 garak 어댑터는 번역 언어 쌍을 중국어↔영어(`zh,en`)로 고정한다. 번역은 공격자 모델이 수행하며, 이 환경에서는 대상 모델이 공격자를 겸한다.

## 사전 준비

관리자는 `redteam-demo` 프로젝트에 대상 모델(InferenceService), 파이프라인 서버(DataSciencePipelinesApplication), EvalHub를 만든다.

```bash
./harness/harness.sh redteam-prep
oc get inferenceservice,evalhub,dspa -n redteam-demo
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd redteam-prep
oc get inferenceservice,evalhub,dspa -n redteam-demo
```

대상 모델은 `Qwen/Qwen2.5-1.5B-Instruct`이다.

## 시연 절차

### 1) 번역 프로브만 지정해 평가 실행

평가자는 `intents` 벤치마크에서 번역 프로브만 실행한다. 실행은 약 20~25분이 걸리므로 시연 전에 수행한다.

```bash
./harness/harness.sh scenario11-run
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd scenario11-run
```

명령은 EvalHub에 `probes: multilingual.TranslationIntent` 파라미터를 가진 평가 작업을 제출한다. 진행은 Dashboard의 **Develop & train** → **Pipelines** → **Runs**에서 확인한다.

### 2) 번역 설정 확인

평가자는 run 그래프의 `garak-scan` 단계에서 **Input/Output** → `config_json`을 열어 `langproviders` 항목(`zh,en`, `en,zh`, `llm.LLMTranslator`)을 보여 준다.

### 3) 리포트 확인

평가자는 리포트를 내려받아 `scan.intents.html`을 연다.

```bash
./harness/harness.sh redteam-report <job-id>
xdg-open harness/reports/<job-id>/scan.intents.html     # macOS: open
```

Windows (PowerShell):

```powershell
.\harness\harness.cmd redteam-report <job-id>
start .\harness\reports\<job-id>\scan.intents.html
```

## 결과 확인

평가자는 같은 명령으로 두 번 실행했다. 공격 프롬프트는 실행마다 새로 합성되므로 수치는 조금 다르다.

| 실행 (job) | Baseline: 영어, 합성 문장 그대로 | SPO + translation: 중국어 탈옥 (영어로 거절된 것만) | 전체 | 번역 시도 |
|------|:---:|:---:|:---:|:---:|
| 1차 `add87389` | 25/80 (31.3%) | 48/55 (87.3%) | 91.3% | 1,092건, 모두 중국어 |
| 2차 `7c3fd6a7` | 35/80 (43.8%) | 37/45 (82.2%) | 90.0% | 896건, 모두 중국어 |

1차 실행의 리포트는 다음과 같다. 혐오 표현, 불법 행위, 허위 정보, 폭력 분류는 중국어 탈옥이 100% 성공했다.

![번역 평가 리포트 개요](images/11/01-translation-report-overview.png)

![번역 평가 리포트 프로브 상세](images/11/02-translation-report-probe-details.png)

중국어 탈옥의 성공률에는 탈옥 템플릿과 번역의 효과가 함께 들어 있다. 같은 모델에 탈옥 템플릿만 영어로 적용한 실행(시나리오 5, SPO 단계)은 81%였으므로, 이 모델에서 번역이 더한 효과는 크지 않다. 다만 두 실행은 합성된 프롬프트가 달라 직접 비교에 한계가 있다.

## Summary

- 평가자는 garak 번역 프로브로 영어로 거절된 공격을 중국어로 다시 시도해 언어 간 방어 격차를 점검했다.
- 영어로 거절된 프롬프트의 82~87%가 중국어 탈옥에서 성공했으며, 두 번의 실행에서 같은 경향이 재현되었다.
- 영어 탈옥(81%)과 비교하면 이 모델에서 번역이 더한 효과는 크지 않았다.

## 운영 가이드

- 서비스가 영어 외의 언어 사용자를 받는다면, 평가자는 영어 점검만으로 안전성을 판단하지 않는다.
- RHOAI 3.5.1에서 EvalHub를 통한 번역 평가는 중국어만 지원한다. 한국어 등 다른 언어는 garak을 직접 실행하고 번역 언어 쌍을 별도로 설정해야 한다.
- 번역 품질이 평가 신뢰도를 좌우한다. 운영 평가에서는 번역과 판정을 대상 모델보다 큰 별도 모델에 맡긴다.
