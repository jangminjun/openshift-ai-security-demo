# 시나리오 6. Red Hat AI 모델 카탈로그 Safety & Security 탭

## 기능 설명

- 분류: 평가 및 보안 > 보안/자산 (GA)
- 모델 카탈로그의 모델 상세 화면은 **Safety and Security Insights** 전용 탭을 제공한다.
- 탭은 프롬프트 주입, 탈옥, 유해 콘텐츠 방어에 대한 garak 스캔(자동 침투 테스트) 결과를 카테고리별 점수로 표시한다.
- 사용자는 모델을 고르는 화면에서 성능·정확도 탭과 함께 보안 점수를 확인한다.

## 사전 준비

별도 리소스는 필요하지 않다. 시연자는 스캔 결과가 있는 모델을 카탈로그 API로 확인한다. 결과가 없는 모델은 탭이 비어 있거나 표시되지 않을 수 있다.

```
HOST=$(oc get route model-catalog-https -n rhoai-model-registries -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://$HOST/api/model_catalog/v1alpha1/models?pageSize=200&filterQuery=artifacts.metricsType%3D%27security-metrics%27" \
  | jq -r '.items[].name'
```

| 시연용 모델 | 전체 공격 성공률 |
|-------------|:---:|
| `RedHatAI/gpt-oss-20b` | 0 |
| `RedHatAI/gemma-4-E4B-it` | 0.15 |
| `RedHatAI/gemma-3-12b-it` | 0.95 |

## 시연 절차

### 1) 모델 카탈로그 진입

시연자는 Dashboard의 **AI hub** → **Models**로 이동해 모델 그룹(Red Hat AI, Red Hat AI validated, Other)을 소개한다.

### 2) 특정 모델 선택 후 Safety and security insights 탭 클릭

시연자는 `gemma-3-12b-it`의 상세 화면을 열고 **Safety and security insights** 탭을 클릭한다. 탭은 Evaluation Name, Category, Benchmark, Evaluation Score(백분율) 열로 점수를 표시하며, 통과/실패 표시는 없다.

![gemma-3-12b-it의 Safety and security insights 탭](images/6/01-gemma-3-safety-insights.png)

### 3) 카테고리별 보안 스캔 스코어 시각적 확인

시연자는 카테고리별 점수를 짚고, `RedHatAI/gpt-oss-20b`의 같은 탭과 비교한다.

## 결과 확인

시연자는 화면의 값을 카탈로그 API로 대조한다.

```
curl -sk -H "Authorization: Bearer $(oc whoami -t)" \
  "https://$HOST/api/model_catalog/v1alpha1/sources/other_models/models/RedHatAI%2Fgemma-3-12b-it/artifacts?filterQuery=metricsType%3D%27security-metrics%27" \
  | jq -r '.items[].customProperties | "\(.result.double_value)\t\(.category.string_value)\t\(.evaluation.string_value)"'
```

| 카테고리 | 다루는 위협 | API 값 | 화면 표시 |
|----------|-------------|:---:|:---:|
| System Prompt Override / Prompt Injection | 프롬프트 주입 | 0.7297 | 73.0% |
| Augmented System Prompt Override | 변형·강화된 프롬프트 주입 | 0 / 0.8 / 0 | 0.0% / 80.0% / 0.0% |
| Compliance / Jailbreak Resistance | 탈옥 | 0.075 | 7.5% |
| Composite Vulnerability Summary | 전체 합산 | 0.95 | 95.0% |

`gemma-3-12b-it`는 탈옥에는 강하지만 프롬프트 주입에는 약하다. 전체 점수 하나로는 이 차이가 드러나지 않는다. 점수 해석 기준은 0.0~0.1 우수, 0.1~0.3 양호, 0.3~0.6 우려, 0.6~1.0 심각이다.

## Summary

- 모델 카탈로그의 Safety and security insights 탭은 garak 점수를 카테고리별 백분율로 표시한다.
- 탭은 통과/실패 표시 없이 점수만 보여 주며, 표시값은 카탈로그 API 값과 일치했다.
- 카테고리별 점수는 전체 점수로 드러나지 않는 약점을 보여 주었다(gemma-3-12b: 탈옥 7.5%, 프롬프트 주입 73.0%).

## 운영 가이드

- 보안 스캔 결과는 별도 문서가 아니라 모델을 선택하는 화면 안에 있다.
- 카테고리별 점수는 모델이 어떤 공격에 약한지를 보여 준다.
- 사용자는 성능·정확도·보안을 같은 화면에서 비교한다.
- 자동화: `harness/harness.sh scenario4-models | scenario4-scores <모델>`
