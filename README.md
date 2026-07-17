[![English](https://img.shields.io/badge/README-English-2563eb)](README_EN.md)

# Server Monitoring

Ubuntu 서버의 자원 상태를 점검하고 이메일로 보고하는 스크립트 모음입니다.

다음 두 종류의 자동화를 제공합니다.

1. 서버 전체 CPU, 메모리, GPU, 스토리지 상태 보고 및 임계치 경고
2. 사용자별 홈 디렉터리 사용량 확인 및 스토리지 정리 안내

## 주요 파일

| 파일 | 설명 |
|---|---|
| `monitor.sh` | 서버 전체 상태 스냅샷 메일 발송 |
| `alert_check.sh` | 메모리 및 전체 스토리지 임계치 점검 |
| `common.sh` | 공통 설정, 자원 수집, 메일 발송 함수 |
| `send_smtp.py` | SMTP 발송 및 HTML 메일 렌더링 |
| `install_cron.sh` | 전체 서버 모니터링 cron 설치 |
| `user_storage_alert.py` | 사용자별 홈 디렉터리 사용량 점검 및 안내 메일 발송 |
| `user_storage_alert.sh` | 환경설정 및 중복 실행 방지를 포함한 실행 진입점 |
| `users.json` | 사용자 이름, 이메일, Linux 계정명 설정 |
| `install_user_storage_cron.sh` | 사용자별 스토리지 점검 cron 설치 |
| `save_storage_alert_test_report.sh` | 사용자 스토리지 안내 메일 HTML 미리보기 생성 |
| `check_requirements.sh` | Ubuntu 실행 의존성 점검 |
| `.env.example` | 서버별 환경설정 예시 |

## Ubuntu 서버 설치

저장소를 clone합니다.

```bash
git clone https://github.com/hun9008/server_monitor.git
cd server_monitor
```

서버별 환경설정 파일을 생성합니다. `.env`에는 SMTP 비밀번호가 포함될 수 있으며 Git에 커밋되지 않습니다.

```bash
cp .env.example .env
chmod 600 .env
nano .env
```

Gmail SMTP 설정 예시:

```bash
MAIL_FROM=younghune135@gmail.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=younghune135@gmail.com
SMTP_PASS="Gmail 앱 비밀번호"
SMTP_TLS=1
SMTP_HTML=1
LOGO_MODE=cid
```

일반 Gmail 비밀번호가 아닌 Gmail 앱 비밀번호를 사용해야 합니다.

필수 프로그램을 확인합니다.

```bash
./check_requirements.sh
```

Ubuntu에서 누락된 패키지를 자동으로 설치하려면:

```bash
sudo ./check_requirements.sh --install
```

## 사용자별 스토리지 알림

### 대상 사용자 설정

`users.json`에서 다음 세 값이 모두 입력된 사용자만 모니터링합니다.

- `name`: 메일에 표시할 이름
- `email`: 알림을 받을 이메일 주소
- `username`: 서버의 Linux 계정명

값이 없으면 빈 문자열 대신 `null`을 사용합니다.

```json
{
  "name": "정용훈",
  "email": "younghune135@unist.ac.kr",
  "username": "hun"
}
```

세 값이 모두 입력된 사람이 N명이라면 알림 기준은 `100/N%`입니다. 현재 대상은 4명이므로 기준은 25%입니다.

사용량은 각 계정의 홈 디렉터리 용량을 해당 홈 디렉터리가 위치한 파일시스템의 전체 용량으로 나누어 계산합니다.

```text
점유율 = 홈 디렉터리 사용량 / 홈 파일시스템 전체 용량 × 100
```

### HTML 메일 미리보기

메일을 발송하지 않고 샘플 HTML을 생성합니다.

```bash
./save_storage_alert_test_report.sh
```

생성 파일:

```text
alert_storage_test.md
alert_storage_test.html
```

### 실제 사용량 무발송 점검

다른 사용자의 홈 디렉터리까지 정확히 읽기 위해 root로 실행합니다.

```bash
sudo ./user_storage_alert.sh --no-send
```

이 명령은 실제 사용량과 점유율만 출력하며 메일을 발송하거나 쿨다운 시간을 기록하지 않습니다.

### 테스트 메일 발송

```bash
sudo ./user_storage_alert.sh --test
```

테스트 모드는 사용량 기준 충족 여부와 관계없이 메일 한 통을 생성합니다. 수신자는 코드에서 다음 주소로 강제되어 있어 다른 사용자에게 테스트 메일이 발송되지 않습니다.

```text
younghune135@unist.ac.kr
```

### 운영 cron 설치

미리보기, 무발송 점검, 테스트 메일까지 확인한 후 설치합니다.

```bash
sudo ./install_user_storage_cron.sh
sudo crontab -l
```

설치되는 항목:

```cron
0 * * * * /설치경로/user_storage_alert.sh >>/tmp/user_storage_alert.log 2>&1 # server_monitoring user_storage_alert
```

cron은 매시간 실행됩니다. 같은 사용자에게 메일이 성공적으로 발송되면 해당 사용자만 9시간 쿨다운에 들어갑니다. 쿨다운 중에도 다른 사용자는 독립적으로 점검하고 발송합니다.

기본 설정:

```bash
USER_STORAGE_COOLDOWN_HOURS=9
USER_STORAGE_STATE_DIR=/설치경로/user_storage_alert_state
USER_STORAGE_LOCK_FILE=/tmp/user-storage-alert.lock
```

필요하면 `.env`에서 값을 변경할 수 있습니다. 메일 발송이 실패하면 쿨다운을 기록하지 않으며 다음 cron 실행 때 다시 시도합니다.

쿨다운을 무시하고 운영 조건을 즉시 다시 점검하려면 다음 옵션을 사용합니다. 조건을 충족한 실제 사용자에게 메일이 발송될 수 있으므로 주의해야 합니다.

```bash
sudo ./user_storage_alert.sh --force
```

로그 확인:

```bash
tail -n 100 /tmp/user_storage_alert.log
```

## 전체 서버 모니터링

스냅샷 미리보기:

```bash
sudo ./save_test_report.sh
```

임계치 경고 미리보기:

```bash
sudo ./save_alert_test_report.sh
```

전체 서버 모니터링 cron 설치:

```bash
sudo ./install_cron.sh
sudo crontab -l
```

설치되는 기본 일정:

```cron
0 9 * * 1 /설치경로/monitor.sh >/tmp/server_monitoring_snapshot.log 2>&1
0 * * * * /설치경로/alert_check.sh >/tmp/server_monitoring_alert.log 2>&1
```

- 서버 스냅샷: 매주 월요일 09:00
- 메모리 및 스토리지 임계치 점검: 매시간
- 전체 서버 경고 기본 쿨다운: 12시간

전체 서버 경고 설정은 `.env`에서 변경할 수 있습니다.

```bash
ALERT_THRESHOLD=70
ALERT_CRITICAL_THRESHOLD=90
ALERT_COOLDOWN_HOURS=12
```

## 다른 Ubuntu 서버 배포 점검 순서

각 서버에서 아래 순서대로 확인한 후 cron을 설치합니다.

```bash
git clone https://github.com/hun9008/server_monitor.git
cd server_monitor

cp .env.example .env
chmod 600 .env
nano .env

./check_requirements.sh
getent passwd parkdw00 heek psm hun
python3 -m json.tool users.json >/dev/null
sudo ./user_storage_alert.sh --no-send
./save_storage_alert_test_report.sh
sudo ./user_storage_alert.sh --test
sudo ./install_user_storage_cron.sh
sudo crontab -l
```

서버마다 다음 사항을 확인해야 합니다.

- `users.json`의 계정이 해당 서버에 실제로 존재하는지
- 계정의 홈 디렉터리가 올바른 파일시스템에 연결되어 있는지
- root에서 모든 홈 디렉터리를 읽을 수 있는지
- SMTP 접속과 Gmail 앱 비밀번호가 유효한지
- 서버 시간대가 원하는 cron 실행 시간과 일치하는지

## 테스트

단위 테스트 실행:

```bash
python3 -m unittest -v test_user_storage_alert.py
```

테스트 항목:

- 이름, 이메일, 계정명이 모두 있는 사용자만 N에 포함
- 홈 사용량 비율 계산
- 테스트 수신자 고정
- 사용자별 9시간 쿨다운

## 참고 사항

- 사용자별 용량 집계는 `du`로 홈 디렉터리 전체를 순회하므로 데이터가 많으면 시간이 걸릴 수 있습니다.
- 이전 점검이 끝나지 않은 상태에서 cron이 다시 실행되면 `flock` 잠금으로 중복 실행을 건너뜁니다.
- 존재하지 않는 계정이나 읽을 수 없는 홈 디렉터리는 해당 사용자만 건너뛰고 로그에 `SKIP`을 남깁니다.
- `nvidia-smi`는 선택 사항이며 NVIDIA GPU가 없는 서버에서도 나머지 모니터링은 동작합니다.
- `LOGO_MODE=cid`는 Gmail과 Outlook 호환성이 가장 좋지만 일부 메일 클라이언트에서는 로고가 첨부 파일처럼 보일 수 있습니다.
- `LOGO_MODE=url`은 첨부 없이 외부 이미지 URL을 사용합니다.
- `.env`, 발송 상태, 생성된 HTML 미리보기는 Git에서 제외됩니다.
