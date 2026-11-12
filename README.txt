훈련병장 회귀자는 전역하고 싶어
================================
Godot로 만드는 Windows 네이티브 2D 군생활·회귀 RPG입니다.
웹/브라우저 게임이 아닙니다. 현재 개발 프로젝트이며 배포용 단독 EXE는 아직 만들지 않았습니다.

다른 데스크탑에서 시작하기
--------------------------
1. Git과 Godot 4.7.2 Standard / Windows x64를 설치합니다.
   현재 이 버전으로 검증했습니다. C#/.NET 에디션이나 Python, Node.js는 실행에 필요하지 않습니다.
   Godot 공식 배포: https://godotengine.org/download/archive/4.7.2-stable/
   winget 사용 시:
     winget install --id Git.Git --exact
     winget install --id GodotEngine.GodotEngine --exact --version 4.7.2
   설치 후 터미널을 새로 엽니다. 버전 설치가 지원되지 않으면 공식 배포에서 해당 버전을 받습니다.

2. 작업할 폴더에서 복제합니다. 저장소가 비공개이면 GitHub 계정 인증이 필요합니다.
     git clone https://github.com/yunjunseong77-cell/ghlrnlwk.git
     cd ghlrnlwk

3. '게임 실행.cmd'를 더블클릭합니다.
   실행기가 원본 이미지·음원을 먼저 가져오기(import)한 후 게임 창을 엽니다.
   최초 실행은 가져오기 때문에 조금 더 걸립니다.
   또는 Godot 프로젝트 목록에서 project.godot를 가져온 뒤 F6이 아닌 F5로 프로젝트를 실행합니다.

4. ZIP으로 설치한 Godot를 자동으로 찾지 못하면 다음처럼 실행합니다.
     powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_game.ps1 -GodotPath "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe"
   GODOT_BIN 환경변수에 Godot 실행 파일의 전체 경로를 지정해도 됩니다.
   실행기는 지정 경로, GODOT_BIN, PATH, 사용자 winget 설치 경로 순으로 찾습니다.

새 채팅에서 개발을 이어갈 때
----------------------------
먼저 AGENTS.md와 docs/개발 인수인계.txt를 읽도록 요청하세요.
시작 안내.txt: 조작과 현재 플레이 범위
docs/훈련과PX안내.txt: 보상·장비·아이템·저장 계약
docs/게임 진행안.txt: 장기 스토리 및 세계관

현재 플레이 가능
----------------
전역날 프롤로그 → 트럭 사고 → 훈련소 이틀 차 회귀 → 퀘스트 → 침상 정리
→ 탑다운 훈련소 탐색 → 짧은 제식 이야기 → 며칠 뒤 사격 훈련 → PX·재도전.
타이틀의 '사격 바로하기'에서 사격만 바로 체험할 수도 있습니다.
PX 장비 8종, 회복 물품 4종, 아이템창, 6부위 장비창, 방향·보행에 맞춘 착용 외형,
HP/SP, 수동 회복 퀵슬롯 1·2와 달리기 지구력을 구현했습니다.
적과의 전투, 능동 스킬, 후반기교육, 8사단 생활은 아직 구현 전입니다.

검증
----
프로젝트 루트의 PowerShell에서:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_checks.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_checks.ps1 -Suite all
기본은 저장·보상·체력/아이템 검증 2개입니다. all은 실제 창을 여는 검증도 순차 실행합니다.
실행 중에는 마우스·키보드 입력을 피하세요. GUI 검증에는 --headless를 붙이지 않습니다.
Godot 직접 지정이 필요하면 -GodotPath에 console.exe 경로를 추가합니다.
테스트 결과 화면은 docs/previews/에 생성되며 Git에는 올리지 않습니다.
검증 스크립트는 별도 테스트 저장 파일을 사용합니다. 재미·연출 품질은 직접 플레이로도 확인합니다.

저장 데이터와 Git
----------------
실제 플레이 저장은 Godot의 user:// 폴더에 있으며 Git에 포함하지 않습니다.
기본 Windows 위치: %APPDATA%\Godot\app_userdata\훈련병장 회귀자는 전역하고 싶어\
progress.cfg: 이름·이야기·본편 진행
training_profile.cfg: 코인·기록·장비·아이템·퀵슬롯·HP/SP
camp_progress.cfg: 탐색 위치와 대화 진행
다른 PC에서 본인의 플레이 기록까지 이어가려면 게임을 종료한 상태에서 위 파일 3개를 별도로 복사합니다.
기존 대상 저장은 덮어쓰기 전에 따로 보관하세요. 개발 프로젝트만 복제하면 새 플레이 기록으로 시작합니다.
.godot/는 재생성되는 캐시이며 build/ 및 검증 스크린샷도 제외합니다.
장면·스크립트 UID와 리소스 .import 설정은 함께 관리합니다. Git LFS는 사용하지 않습니다.

음원·이미지·폰트
----------------
실행에 필요한 이미지, 폰트, 음원은 assets/에 포함되어 있습니다.
원래 PC의 Downloads 폴더나 .codex/generated_images 폴더는 필요하지 않습니다.
사용자 제공 BGM 연결: assets/audio/음원안내.txt
녹음 효과음 출처: assets/audio/출처.txt, assets/audio/사격효과음출처.txt
이미지 생성 기록: docs/asset-prompts.json, assets/art/*/prompts.txt
폰트 라이선스: assets/fonts/*-OFL.txt
이 프로젝트 전체에 별도 오픈소스 라이선스를 부여한 것은 아닙니다.
