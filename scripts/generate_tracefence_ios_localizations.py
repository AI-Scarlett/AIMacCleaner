#!/usr/bin/env python3
"""Generate TraceFence Sentinel localization resources from the English key set."""

from __future__ import annotations

import json
import re
from pathlib import Path

from opencc import OpenCC


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "TraceFenceIOS/TraceFenceIOS/Resources"
SOURCE = RESOURCES / "en.lproj/Localizable.strings"
LINE_PATTERN = re.compile(r'^\s*("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*");\s*$')


# Columns: source key, Japanese, Korean, Maltese. Empty cells deliberately fall
# back to English, matching the macOS Localizer contract for optional languages.
TRANSLATIONS = r"""
API 关闭	API オフ	API 꺼짐	API Mitfi
API 在线	API オンライン	API 온라인	API Online
Agent 任务监控	Agent タスク監視	Agent 작업 모니터링	Monitoraġġ tal-Kompiti tal-Agent
Agent 会话	Agent セッション	Agent 세션	Sessjoni tal-Agent
Agent 会话和远程控制已锁定	Agent セッションとリモート操作はロックされています	Agent 세션 및 원격 제어가 잠겨 있습니다	Is-sessjonijiet u l-kontrolli remoti huma msakkra
Agent 提问	Agent の質問	Agent 질문	Mistoqsija tal-Agent
Agent 权限请求	Agent 権限リクエスト	Agent 권한 요청	Talba għall-Permess tal-Agent
Agent 正在执行	Agent 実行中	Agent 실행 중	L-Agent qed jaħdem
Agent 监控	Agent 監視	Agent 모니터	Monitoraġġ tal-Agent
Agent 连接器	Agent コネクタ	Agent 커넥터	Konnetturi tal-Agent
App Store 标准订阅	App Store 標準サブスクリプション	App Store 표준 구독	Abbonament Standard tal-App Store
Codex 原生控制	Codex ネイティブ制御	Codex 네이티브 제어	Kontroll Nattiv ta' Codex
Codex 桌面控制	Codex デスクトップ制御	Codex 데스크톱 제어	Kontroll tad-Desktop ta' Codex
Core 在线	Core オンライン	Core 온라인	Core Online
Core 未连接	Core 未接続	Core 연결 끊김	Core Mhux Konness
Hook 回复	Hook 応答	Hook 응답	Tweġiba tal-Hook
Hook 审批	Hook 承認	Hook 승인	Approvazzjoni tal-Hook
Mac 上安装并可被 TraceFence 识别的 Agent 会显示在这里。	Mac にインストールされ、TraceFence が認識した Agent がここに表示されます。	Mac에 설치되어 TraceFence가 인식한 Agent가 여기에 표시됩니다。	
Mac 可控会话	Mac 制御セッション	Mac 제어 세션	Sessjoni Kontrollabbli tal-Mac
Mac 监控	Mac 監視	Mac 모니터링	Monitoraġġ tal-Mac
Mac 端准备	Mac の準備	Mac 준비	Ipprepara l-Mac
Mac 地址	Mac アドレス	Mac 주소	Indirizz tal-Mac
Mac 正在记录 Agent 操作和系统状态。	Mac は Agent の操作とシステム状態を記録しています。	Mac이 Agent 활동과 시스템 상태를 기록하고 있습니다。	
Mac 端已声明此任务可远程控制。	Mac はこのタスクをリモート制御可能と報告しています。	Mac에서 이 작업을 원격 제어할 수 있다고 보고했습니다。	
Mac 端没有创建这个会话。	Mac はこのセッションを作成しませんでした。	Mac에서 이 세션을 만들지 못했습니다。	
Mac 端没有执行这次远程控制。	Mac はこのリモート操作を実行しませんでした。	Mac에서 이 원격 제어를 실행하지 못했습니다。	
Mac 端没有接受这次审批操作。	Mac はこの承認操作を受け付けませんでした。	Mac에서 이 승인 작업을 수락하지 않았습니다。	
Mac 端没有接管这个任务。	Mac はこのタスクを引き継ぎませんでした。	Mac에서 이 작업을 인계받지 못했습니다。	
Mac 端进入设置，打开 iOS 远程控制，点击“复制 iOS 配对信息”，再粘贴到这里。	Mac の設定で iOS リモート制御を開き、「iOS ペアリング情報をコピー」を選んでここに貼り付けます。	Mac 설정에서 iOS 원격 제어를 열고 ‘iOS 페어링 정보 복사’를 누른 뒤 여기에 붙여 넣으세요。	
Mac 端远程控制服务已关闭。	Mac のリモート制御サービスは無効です。	Mac의 원격 제어 서비스가 꺼져 있습니다。	
Mac 返回的数据无法识别。请确认连接的是 TraceFence。	Mac から認識できないデータが返されました。TraceFence に接続していることを確認してください。	Mac에서 인식할 수 없는 데이터를 반환했습니다. TraceFence에 연결했는지 확인하세요。	
同一 Wi-Fi / 局域网	同じ Wi-Fi / LAN	동일 Wi-Fi / LAN	L-istess Wi-Fi / LAN
私有 VPN / Tailnet	プライベート VPN / Tailnet	개인 VPN / Tailnet	VPN Privat / Tailnet
端口转发 + DDNS	ポート転送 + DDNS	포트 포워딩 + DDNS	Port Forwarding + DDNS
用户自有反向隧道	ユーザー所有のリバーストンネル	사용자 소유 역방향 터널	Reverse Tunnel Tiegħek
无后端远程控制	バックエンドなしのリモート制御	백엔드 없는 원격 제어	Kontroll Remot Mingħajr Backend
上架版	App Store 版	App Store 버전	App Store
官网版	直販版	직접 배포 버전	Dirett
官网标准订阅	直販標準サブスクリプション	직접 배포 표준 구독	Standard Dirett
官网增强订阅	直販拡張サブスクリプション	직접 배포 고급 구독	Avvanzat Dirett
历史授权	旧ライセンス	기존 라이선스	Liċenzja Preċedenti
未知方案	不明なプラン	알 수 없는 요금제	Pjan Mhux Magħruf
未知渠道	不明な配布経路	알 수 없는 채널	Kanal Mhux Magħruf
未订阅	未登録	구독 안 함	Mhux Abbonat
总览	概要	개요	Ħarsa Ġenerali
监控	監視	모니터	Monitoraġġ
会话	セッション	세션	Sessjonijiet
确认	承認	승인	Approvazzjonijiet
设置	設定	설정	Issettjar
连接	接続	연결	Konnessjoni
当前 Mac	現在の Mac	현재 Mac	Mac Attwali
地址	エンドポイント	엔드포인트	Endpoint
当前连接	現在の接続	현재 연결	Konnessjoni Attwali
连接设置	接続設定	연결 설정	Issettjar tal-Konnessjoni
连接说明	接続ガイド	연결 안내	Gwida tal-Konnessjoni
连接或更换 Mac	Mac をペアリングまたは変更	Mac 연결 또는 변경	Qabbad jew Ibdel il-Mac
已连接常驻 Agent Core	バックグラウンド Agent Core に接続済み	백그라운드 Agent Core에 연결됨	Konness ma' Agent Core fl-Isfond
已连接 Mac App	Mac App に接続済み	Mac App에 연결됨	Konness mal-App tal-Mac
尚未连接 Mac。	Mac はまだ接続されていません。	아직 Mac에 연결되지 않았습니다。	L-ebda Mac mhu konness.
立即重连	今すぐ再接続	지금 다시 연결	Erġa' Qabbad Issa
语言	言語	언어	Lingwa
显示语言	表示言語	표시 언어	Lingwa tal-Wiri
跟随系统	システムに従う	시스템 설정 사용	Segwi s-Sistema
简体中文	簡体字中国語	중국어 간체	Ċiniż Simplifikat
安全	セキュリティ	보안	Sigurtà
立即锁定	今すぐロック	지금 잠그기	Sakkar Issa
隐私	プライバシー	개인정보 보호	Privatezza
隐私协议	プライバシーポリシー	개인정보 처리방침	Politika tal-Privatezza
完成	完了	완료	Lest
关闭	閉じる	닫기	Agħlaq
开始配对	ペアリングを開始	페어링 시작	Ibda l-Pairing
配对 Mac	Mac をペアリング	Mac 페어링	Qabbad il-Mac
从 Mac 导入	Mac から読み込む	Mac에서 가져오기	Importa mill-Mac
手动连接	手動接続	수동 연결	Konnessjoni Manwali
保存并测试连接	保存して接続をテスト	저장 및 연결 테스트	Issejvja u Ittestja
导入并测试	読み込んでテスト	가져오기 및 테스트	Importa u Ittestja
当前连接	現在の接続	현재 연결	Konnessjoni Attwali
Mac 地址	Mac アドレス	Mac 주소	Indirizz tal-Mac
密钥	トークン	토큰	Token
配对密钥	ペアリングトークン	페어링 토큰	Token tal-Pairing
渠道	配布経路	채널	Kanal
上次成功	前回成功	마지막 성공	L-Aħħar Suċċess
自动试连地址 %lld	自動試行アドレス %lld 件	자동 연결 시도 주소 %lld개	Indirizzi Ppruvati %lld
移除这台 Mac	この Mac を削除	이 Mac 제거	Neħħi dan il-Mac
还没有保存 Mac。	保存された Mac はありません。	저장된 Mac이 없습니다。	L-ebda Mac mhu ssejvjat.
扫码	スキャン	스캔	Skennja
粘贴	貼り付け	붙여넣기	Waħħal
扫描配对码	ペアリングコードをスキャン	페어링 코드 스캔	Skennja l-Kodiċi tal-Pairing
扫描 Mac 上的 TraceFence 配对二维码	Mac の TraceFence ペアリング QR コードをスキャン	Mac의 TraceFence 페어링 QR 코드를 스캔하세요	Skennja l-QR tal-Pairing fuq il-Mac
需要相机权限才能扫描配对二维码。	ペアリング QR コードのスキャンにはカメラ権限が必要です。	페어링 QR 코드를 스캔하려면 카메라 권한이 필요합니다。	Hemm bżonn permess tal-kamera biex tiskennja l-QR.
请在系统设置中允许 TraceFence 使用相机。	設定で TraceFence のカメラ使用を許可してください。	설정에서 TraceFence의 카메라 사용을 허용하세요。	Ippermetti l-kamera għal TraceFence fl-Issettjar.
没有可用相机。	利用できるカメラがありません。	사용 가능한 카메라가 없습니다。	M'hemmx kamera disponibbli.
无法使用相机输入。	カメラ入力を使用できません。	카메라 입력을 사용할 수 없습니다。	L-input tal-kamera mhuwiex disponibbli.
无法读取二维码。	QR コードを読み取れません。	QR 코드를 읽을 수 없습니다。	Ma setax jinqara l-kodiċi QR.
实时 Agent 控制台	リアルタイム Agent コンソール	실시간 Agent 콘솔	Console tal-Agent f'Ħin Reali
Agent 任务监控	Agent タスク監視	Agent 작업 모니터링	Monitoraġġ tal-Kompiti tal-Agent
任务范围	タスク範囲	작업 범위	Ambitu tal-Kompiti
全部任务	すべてのタスク	모든 작업	Il-Kompiti Kollha
全部	すべて	전체	Kollha
待处理	要対応	처리 필요	Pendenti
可控	制御可能	제어 가능	Kontrollabbli
仅监控	監視のみ	모니터 전용	Monitoraġġ Biss
仅可监控	監視のみ	모니터 전용	Monitoraġġ Biss
可操作	操作可能	작업 가능	Azzjonabbli
可用	利用可能	사용 가능	Lest
告警	アラート	알림	Twissijiet
命令确认	コマンド承認	명령 승인	Approvazzjonijiet tal-Kmand
当前没有告警	現在アラートはありません	현재 알림 없음	Ebda Twissija
当前没有待确认命令	承認待ちのコマンドはありません	승인 대기 중인 명령 없음	Ebda Kmand Pendenti
等待输入、可接管任务、受限控制和待处理事件会出现在这里。	入力待ち、引き継ぎ可能、制限付き制御、要対応イベントがここに表示されます。	입력 대기, 인계 가능, 제한된 제어 및 처리 대기 이벤트가 여기에 표시됩니다。	
搜索任务、项目、会话	タスク、プロジェクト、セッションを検索	작업, 프로젝트, 세션 검색	Fittex kompiti, proġetti u sessjonijiet
没有符合条件的任务	一致するタスクはありません	일치하는 작업 없음	Ebda Kompitu Jaqbel
实时会话	リアルタイムセッション	실시간 세션	Sessjonijiet f'Ħin Reali
实时会话管理	リアルタイムセッション管理	실시간 세션 관리	Ġestjoni tas-Sessjonijiet
新建	新規	새로 만들기	Oħloq
新建会话	新しいセッション	새 세션	Sessjoni Ġdida
新建可控会话	新しい制御セッション	새 제어 세션	Sessjoni Kontrollabbli Ġdida
没有可控会话	制御可能なセッションはありません	제어 가능한 세션 없음	Ebda Sessjoni Kontrollabbli
没有可新建的本地 Agent	起動できるローカル Agent はありません	시작할 수 있는 로컬 Agent 없음	Ebda Agent Lokali Disponibbli
本地 Agent	ローカル Agent	로컬 Agent	Agent Lokali
本地会话	ローカルセッション	로컬 세션	Sessjoni Lokali
可控会话	制御可能なセッション	제어 가능한 세션	Sessjoni Kontrollabbli
可控 Agent	制御可能な Agent	제어 가능한 Agent	Agent Kontrollabbli
控制入口	操作入口	제어 진입점	Kontrolli
接管任务	タスクを引き継ぐ	작업 인계	Ħu l-Kontroll tal-Kompitu
接管并发送	引き継いで送信	인계 후 전송	Ħu l-Kontroll u Ibgħat
接管并发送指令	引き継いで指示を送信	인계 후 지시 전송	Ħu l-Kontroll u Ibgħat Struzzjoni
会话指令	セッション指示	세션 지시	Struzzjoni tas-Sessjoni
发送指令	指示を送信	지시 전송	Ibgħat Struzzjoni
插入指令	指示を挿入	지시 삽입	Daħħal Struzzjoni
回复 Agent	Agent に返信	Agent에 응답	Wieġeb lill-Agent
发送	送信	보내기	Ibgħat
启动	開始	시작	Ibda
停止	停止	중지	Waqqaf
暂停	一時停止	일시 정지	Waqqaf Temporanjament
中断	中断	중단	Interrompi
终止	終了	종료	Temm
取消	キャンセル	취소	Ikkanċella
只读	読み取り専用	읽기 전용	Qari Biss
受限控制	制限付き制御	제한된 제어	Kontroll Limitat
可接管任务	引き継ぎ可能	인계 가능	Jista' Jittieħed
空闲	待機中	유휴	Wieqaf
就绪	準備完了	준비됨	Lest
执行中	実行中	실행 중	Qed Jaħdem
待审批	承認待ち	승인 대기	Qed Jistenna Approvazzjoni
待回复	返信待ち	응답 대기	Qed Jistenna Tweġiba
等待确认	承認待ち	승인 대기	Qed Jistenna Approvazzjoni
等待指令	指示待ち	지시 대기	Qed Jistenna Struzzjoni
已暂停	一時停止済み	일시 정지됨	Imwaqqaf Temporanjament
已完成	完了	완료됨	Lest
异常	エラー	오류	Żball
注意	注意	주의	Attenzjoni
风险	リスク	위험	Riskju
高危	重大	심각	Kritiku
需要关注	要確認	주의 필요	Jeħtieġ Attenzjoni
需要处理	対応が必要	조치 필요	Jeħtieġ Azzjoni
能力未知	機能不明	알 수 없는 기능	Kapaċità Mhux Magħrufa
整理上下文	コンテキスト整理中	컨텍스트 정리 중	Qed Jorganizza l-Kuntest
操作审批	操作承認	작업 승인	Approvazzjoni tal-Operazzjoni
计划审批	プラン承認	계획 승인	Approvazzjoni tal-Pjan
批准并继续	承認して続行	승인 후 계속	Approva u Kompli
拒绝	拒否	거부	Irrifjuta
拒绝并改指令	拒否して指示を変更	거부 후 지시 변경	Irrifjuta u Ibdel
拒绝后发送替代指令（可选）	拒否後に代替指示を送信（任意）	거부 후 대체 지시 전송(선택 사항)	
输入要发送给 Agent 的下一步要求、回复或修正说明	Agent に送る次の要求、返信、修正内容を入力	Agent에 보낼 다음 요청, 응답 또는 수정 사항을 입력하세요	
输入要交给这个任务的下一步指令	このタスクへの次の指示を入力	이 작업에 전달할 다음 지시를 입력하세요	
可留空，创建后也可以继续发送新指令	空欄でも構いません。作成後も指示を送信できます。	비워 둘 수 있으며 만든 후에도 지시를 보낼 수 있습니다。	
确认与告警	承認とアラート	승인 및 알림	Approvazzjonijiet u Twissijiet
权限请求、计划确认和等待回复会集中出现在这里。	権限リクエスト、プラン承認、返信待ちがここに集約されます。	권한 요청, 계획 승인 및 응답 대기가 여기에 표시됩니다。	
内存压力	メモリ負荷	메모리 압력	Pressjoni tal-Memorja
剩余空间	空き容量	남은 공간	Spazju Ħieles
磁盘已用	ディスク使用量	디스크 사용량	Diska Użata
监控中	監視中	모니터링 중	Qed Jimmonitorja
未开启	オフ	꺼짐	Mitfi
配对内容不是有效文本。请从 Mac 端复制完整的 iOS 配对信息。	ペアリング情報が有効なテキストではありません。Mac から完全な iOS ペアリング情報をコピーしてください。	페어링 내용이 올바르지 않습니다. Mac에서 전체 iOS 페어링 정보를 복사하세요。	
请先配对一台 Mac。	先に Mac をペアリングしてください。	먼저 Mac을 페어링하세요。	L-ewwel qabbad Mac.
请填写 Mac 地址和配对密钥。	Mac アドレスとペアリングトークンを入力してください。	Mac 주소와 페어링 토큰을 입력하세요。	Daħħal l-indirizz tal-Mac u t-token tal-pairing.
正在连接 Mac	Mac に接続中	Mac 연결 중	Qed Jikkonnettja mal-Mac
正在暂停 Agent 任务	Agent タスクを一時停止中	Agent 작업 일시 정지 중	Qed Iwaqqaf il-Kompitu
正在终止 Agent 任务	Agent タスクを終了中	Agent 작업 종료 중	Qed Itemm il-Kompitu
正在发送指令	指示を送信中	지시 전송 중	Qed Jibgħat Struzzjoni
正在恢复 Agent 任务	Agent タスクを再開中	Agent 작업 재개 중	Qed Ikompli l-Kompitu
正在批准 Agent 操作	Agent 操作を承認中	Agent 작업 승인 중	Qed Japprova l-Operazzjoni
正在拒绝 Agent 操作	Agent 操作を拒否中	Agent 작업 거부 중	Qed Jirrifjuta l-Operazzjoni
正在启动 Mac 监控	Mac 監視を開始中	Mac 모니터링 시작 중	Qed Jibda l-Monitoraġġ
正在停止 Mac 监控	Mac 監視を停止中	Mac 모니터링 중지 중	Qed Iwaqqaf il-Monitoraġġ
正在验证	認証中	인증 중	Qed Jawtentika
设备密码	デバイスのパスコード	기기 암호	Kodiċi tal-Apparat
身份验证已取消。	認証がキャンセルされました。	인증이 취소되었습니다。	L-awtentikazzjoni ġiet ikkanċellata.
身份验证失败，请重试。	認証に失敗しました。もう一度お試しください。	인증에 실패했습니다. 다시 시도하세요。	L-awtentikazzjoni falliet. Erġa' pprova.
请先使用 Face ID、Touch ID 或设备密码解锁。	Face ID、Touch ID、またはデバイスのパスコードでロックを解除してください。	Face ID, Touch ID 또는 기기 암호로 먼저 잠금을 해제하세요。	L-ewwel iftaħ b'Face ID, Touch ID jew il-kodiċi tal-apparat.
远程控制需要有效订阅或试用。	リモート制御には有効なサブスクリプションまたはトライアルが必要です。	원격 제어에는 활성 구독 또는 평가판이 필요합니다。	Il-kontroll remot jeħtieġ abbonament jew prova attiva.
配对密钥不正确。请在 Mac 端重置并重新复制配对信息。	ペアリングトークンが正しくありません。Mac でリセットし、ペアリング情報を再度コピーしてください。	페어링 토큰이 올바르지 않습니다. Mac에서 재설정한 뒤 페어링 정보를 다시 복사하세요。	
还没有连接 Mac	Mac 未接続	Mac 연결 안 됨	L-ebda Mac Konness
我的 Mac	自分の Mac	내 Mac	Il-Mac Tiegħi
手动地址	手動アドレス	수동 주소	Indirizz Manwali
已保存地址	保存済みアドレス	저장된 주소	Indirizz Issejvjat
扫码地址	スキャンしたアドレス	스캔한 주소	Indirizz Skennjat
局域网地址	LAN アドレス	LAN 주소	Indirizz LAN
已保存	保存済み	저장됨	Issejvjat
"""


# Technical control-plane copy is fully localized for Japanese and Korean.
# Maltese keeps the macOS policy of falling back to English for long-form
# technical explanations while retaining localized navigation and actions.
TECHNICAL_TRANSLATIONS = r"""
Agent 已完成或已清理，TraceFence 没有可继续的运行时会话。	Agent は完了またはクリーンアップ済みのため、続行できるランタイムセッションがありません。	Agent가 완료되었거나 정리되어 계속할 런타임 세션이 없습니다。	
Claude Code CLI 已可用于远程会话控制。	Claude Code CLI はリモートセッション制御に使用できます。	Claude Code CLI를 원격 세션 제어에 사용할 수 있습니다。	
Claude Code 会话已经空闲。	Claude Code セッションはすでにアイドル状態です。	Claude Code 세션은 이미 유휴 상태입니다。	
Claude Code 凭据无效。请在 Mac 登录 Claude Code 或更新 API 提供商凭据后重试。	Claude Code の認証情報が無効です。Mac で Claude Code にログインするか、API プロバイダーの認証情報を更新してから再試行してください。	Claude Code 자격 증명이 올바르지 않습니다. Mac에서 Claude Code에 로그인하거나 API 제공자 자격 증명을 업데이트한 뒤 다시 시도하세요。	
Claude Code 后台任务已停止。	Claude Code のバックグラウンドタスクを停止しました。	Claude Code 백그라운드 작업이 중지되었습니다。	
Claude Code 提供商请求失败。请在 Mac 检查 Claude Code 登录或 API 提供商配置后重试。	Claude Code プロバイダーへのリクエストに失敗しました。Mac で Claude Code のログインまたは API プロバイダー設定を確認してから再試行してください。	Claude Code 제공자 요청에 실패했습니다. Mac에서 Claude Code 로그인 또는 API 제공자 설정을 확인한 뒤 다시 시도하세요。	
Claude Code 登录无效。请在 Mac 终端运行 claude auth login；Claude Desktop 与 Claude Code 使用独立登录。	Claude Code のログインが無効です。Mac のターミナルで claude auth login を実行してください。Claude Desktop と Claude Code のログインは別です。	Claude Code 로그인이 올바르지 않습니다. Mac 터미널에서 claude auth login을 실행하세요. Claude Desktop과 Claude Code는 별도로 로그인합니다。	
Claude Desktop 没有暴露 TraceFence 可调用的本地会话控制接口；TraceFence 可以监控它，并在本机安装 claude CLI 时接管到 Claude Code 可控会话。	Claude Desktop は TraceFence から呼び出せるローカルセッション制御 API を公開していません。TraceFence は監視でき、claude CLI がインストールされていれば Claude Code の制御セッションとして引き継げます。	Claude Desktop은 TraceFence가 호출할 수 있는 로컬 세션 제어 API를 제공하지 않습니다. TraceFence는 이를 모니터링하고, claude CLI가 설치되어 있으면 Claude Code 제어 세션으로 인계할 수 있습니다。	
Cloudflare Tunnel、frp、SSH reverse tunnel 或自己的 VPS。	Cloudflare Tunnel、frp、SSH リバーストンネル、または自分の VPS を使用します。	Cloudflare Tunnel, frp, SSH 역방향 터널 또는 자체 VPS를 사용합니다。	
Codex Desktop 初始化失败	Codex Desktop の初期化に失敗しました	Codex Desktop 초기화 실패	
Codex Desktop 初始化没有返回响应	Codex Desktop の初期化から応答がありません	Codex Desktop 초기화 응답 없음	
Codex Desktop 初始化请求写入失败	Codex Desktop に初期化リクエストを送信できませんでした	Codex Desktop 초기화 요청을 전송하지 못했습니다	
Codex Desktop 请求写入失败	Codex Desktop にリクエストを送信できませんでした	Codex Desktop에 요청을 전송하지 못했습니다	
Codex 会话	Codex セッション	Codex 세션	
Codex 官方 app-server 已连接。	公式 Codex app-server に接続しました。	공식 Codex app-server에 연결되었습니다。	
Cursor Desktop 当前只作为桌面进程监控；如安装 cursor-agent，可接管到 TraceFence 可控 CLI 会话。	Cursor Desktop は現在デスクトッププロセスとしてのみ監視されます。cursor-agent がインストールされていれば、TraceFence の制御可能な CLI セッションとして引き継げます。	Cursor Desktop은 현재 데스크톱 프로세스로만 모니터링됩니다. cursor-agent가 설치되어 있으면 TraceFence 제어 가능 CLI 세션으로 인계할 수 있습니다。	
Mac 上的 Codex 任务已中断。	Mac 上の Codex タスクを中断しました。	Mac의 Codex 작업이 중단되었습니다。	
Mac 和 iPhone 在同一个网络中。	Mac と iPhone は同じネットワーク上にあります。	Mac과 iPhone이 동일한 네트워크에 있습니다。	
Mac 和 iPhone 必须安装并登录同一个 Tailscale、ZeroTier、WireGuard 或公司 VPN。	Mac と iPhone の両方に同じ Tailscale、ZeroTier、WireGuard、または社内 VPN をインストールしてログインする必要があります。	Mac과 iPhone 모두 동일한 Tailscale, ZeroTier, WireGuard 또는 회사 VPN을 설치하고 로그인해야 합니다。	
Mac 和 iPhone 断网时，已提交到 Mac 的任务仍可继续，但新的远程操作需要恢复连接。	Mac と iPhone の接続が切れても Mac に送信済みのタスクは続行できますが、新しいリモート操作には再接続が必要です。	Mac과 iPhone의 연결이 끊겨도 Mac에 제출된 작업은 계속 실행될 수 있지만, 새 원격 작업을 하려면 연결이 복구되어야 합니다。	
Mac 地址无效。请粘贴配对信息，或输入 http://192.168.x.x:17895。	Mac の接続先が無効です。ペアリング情報を貼り付けるか、http://192.168.x.x:17895 のようなアドレスを入力してください。	Mac 엔드포인트가 올바르지 않습니다. 페어링 정보를 붙여 넣거나 http://192.168.x.x:17895 같은 주소를 입력하세요。	
Mac 进入系统睡眠或断网后，新的远程操作仍需等待网络恢复。	Mac がスリープまたはネットワーク切断状態になると、新しいリモート操作は接続の復旧を待つ必要があります。	Mac이 잠자기 상태이거나 네트워크 연결이 끊기면 새 원격 작업은 연결이 복구될 때까지 기다려야 합니다。	
Shell · 可控会话	Shell · 制御可能なセッション	Shell · 제어 가능한 세션	
Tailscale、ZeroTier、WireGuard 或公司 VPN 同时连接两端。	Tailscale、ZeroTier、WireGuard、または社内 VPN で両方のデバイスを接続します。	Tailscale, ZeroTier, WireGuard 또는 회사 VPN으로 두 기기를 모두 연결합니다。	
TraceFence Agent Core 已作为常驻服务连接。	TraceFence Agent Core がバックグラウンドサービスとして接続されています。	TraceFence Agent Core가 백그라운드 서비스로 연결되었습니다。	
TraceFence Agent Core 是独立常驻服务，可在 Mac App 窗口关闭或屏幕锁定后继续控制真实会话。	TraceFence Agent Core は独立したバックグラウンドサービスで、Mac App のウインドウを閉じた後や画面ロック中も実際のセッションを制御できます。	TraceFence Agent Core는 독립 백그라운드 서비스이며, Mac App 창을 닫거나 화면이 잠긴 뒤에도 실제 세션을 계속 제어할 수 있습니다。	
TraceFence Agent Core 通过 Mac 本机桌面 IPC 控制真实会话，不会创建替代 Shell 会话。	TraceFence Agent Core は Mac のローカルデスクトップ IPC を通じて実際のセッションを制御し、代替の Shell セッションは作成しません。	TraceFence Agent Core는 Mac의 로컬 데스크톱 IPC를 통해 실제 세션을 제어하며 대체 Shell 세션을 만들지 않습니다。	
TraceFence Sentinel 不使用 TraceFence 后端中转。iPhone 会直接连接你配对的 Mac；配对密钥仅保存在本机。	TraceFence Sentinel は TraceFence の中継バックエンドを使用しません。iPhone はペアリングした Mac に直接接続し、ペアリングトークンはこのデバイス内にのみ保存されます。	TraceFence Sentinel은 TraceFence 중계 백엔드를 사용하지 않습니다. iPhone은 페어링한 Mac에 직접 연결하며 페어링 토큰은 이 기기에만 저장됩니다。	
TraceFence Sentinel 用于从 iPhone 监控和控制你自己 Mac 上的 TraceFence Agent 控制面。	TraceFence Sentinel を使うと、iPhone から自分の Mac 上の TraceFence Agent 制御プレーンを監視・操作できます。	TraceFence Sentinel을 사용하면 iPhone에서 자신의 Mac에 있는 TraceFence Agent 제어 영역을 모니터링하고 제어할 수 있습니다。	
TraceFence 不运营中继，隧道服务由用户自己负责。	TraceFence は中継サービスを運営しません。トンネルサービスはユーザー自身で管理します。	TraceFence는 중계 서비스를 운영하지 않습니다. 터널 서비스는 사용자가 직접 관리해야 합니다。	
TraceFence 只能监控此任务，当前没有找到可安全控制的终端进程或 Hook bridge。	安全に制御できるターミナルプロセスまたは Hook bridge が見つからないため、TraceFence はこのタスクを監視することしかできません。	안전하게 제어할 수 있는 터미널 프로세스 또는 Hook bridge를 찾지 못해 TraceFence는 이 작업을 모니터링만 할 수 있습니다。	
TraceFence 通过 Mac 本机 Codex app-server 控制真实会话，不会创建替代 Shell 会话。	TraceFence は Mac のローカル Codex app-server を通じて実際のセッションを制御し、代替の Shell セッションは作成しません。	TraceFence는 Mac의 로컬 Codex app-server를 통해 실제 세션을 제어하며 대체 Shell 세션을 만들지 않습니다。	
Trae Desktop 当前只作为桌面进程监控；需要对应 CLI 或 Hook bridge 才能远程插入指令。	Trae Desktop は現在デスクトッププロセスとしてのみ監視されます。リモートで指示を挿入するには、対応する CLI または Hook bridge が必要です。	Trae Desktop은 현재 데스크톱 프로세스로만 모니터링됩니다. 원격으로 지시를 삽입하려면 호환 CLI 또는 Hook bridge가 필요합니다。	
iOS 客户端不会登录 TraceFence 云服务，也不会把 Agent 数据传给 TraceFence。它只是用配对密钥直连你的 Mac。	iOS App は TraceFence のクラウドサービスにログインせず、Agent データを TraceFence に送信しません。ペアリングトークンを使って Mac に直接接続するだけです。	iOS App은 TraceFence 클라우드 서비스에 로그인하거나 Agent 데이터를 TraceFence로 보내지 않습니다. 페어링 토큰으로 Mac에 직접 연결할 뿐입니다。	
iPhone 作为 TraceFence 控制台使用：监控所有 Agent 任务，在会话里发送新指令、暂停、终止，在确认里处理审批和告警。	iPhone を TraceFence コンソールとして使用します。すべての Agent タスクを監視し、セッションで新しい指示の送信、一時停止、終了を行い、承認画面で承認とアラートを処理できます。	iPhone을 TraceFence 콘솔로 사용하여 모든 Agent 작업을 모니터링하고, 세션에서 새 지시 전송, 일시 정지, 종료를 수행하며, 승인 화면에서 승인과 알림을 처리할 수 있습니다。	
中断请求已发送给 Mac 上当前打开的 Codex 任务.	現在 Mac で開いている Codex タスクに中断リクエストを送信しました。	현재 Mac에서 열려 있는 Codex 작업에 중단 요청을 보냈습니다。	
从 Mac 上接管监控任务，或新建一个可控会话后会出现在这里。	Mac 上の監視タスクを引き継ぐか、新しい制御セッションを作成するとここに表示されます。	Mac의 모니터링 작업을 인계하거나 새 제어 세션을 만들면 여기에 표시됩니다。	
创建新 PTY 会话需要打开 Mac 版 TraceFence。	新しい PTY セッションを作成するには Mac 版 TraceFence を開く必要があります。	새 PTY 세션을 만들려면 Mac용 TraceFence를 열어야 합니다。	
刷新后，Mac 已发现的 Agent 任务会按能力出现在这里。	更新すると、Mac で検出された Agent タスクが機能に応じてここに表示されます。	새로 고치면 Mac에서 발견된 Agent 작업이 기능에 따라 여기에 표시됩니다。	
发送指令会在这个真实 Agent 会话中创建新 turn。	指示を送信すると、この実際の Agent セッションに新しいターンが作成されます。	지시를 보내면 이 실제 Agent 세션에 새 턴이 생성됩니다。	
发送指令会在这个真实 Codex 会话中创建新 turn，并同步显示在 Mac 客户端。	指示を送信すると、この実際の Codex セッションに新しいターンが作成され、Mac クライアントにも同期して表示されます。	지시를 보내면 이 실제 Codex 세션에 새 턴이 생성되고 Mac 클라이언트에도 동기화되어 표시됩니다。	
发送的内容会插入当前 Agent turn；也可以先中断，再发送新的后续指令。	送信内容は現在の Agent ターンに挿入されます。先に中断してから新しい後続指示を送信することもできます。	보낸 내용은 현재 Agent 턴에 삽입됩니다. 먼저 중단한 뒤 새 후속 지시를 보낼 수도 있습니다。	
发送的内容会插入当前 Codex turn；也可以先中断，再发送新的后续指令。	送信内容は現在の Codex ターンに挿入されます。先に中断してから新しい後続指示を送信することもできます。	보낸 내용은 현재 Codex 턴에 삽입됩니다. 먼저 중단한 뒤 새 후속 지시를 보낼 수도 있습니다。	
只适合高级用户；公网场景应使用 HTTPS 或安全隧道。	上級ユーザー向けです。インターネット公開時は HTTPS または安全なトンネルを使用してください。	고급 사용자에게만 적합합니다. 공용 인터넷에서는 HTTPS 또는 보안 터널을 사용하세요。	
可从 iPhone 发送新指令	iPhone から新しい指示を送信できます	iPhone에서 새 지시를 보낼 수 있음	
可以从 iPhone 启动 Mac 监控。	iPhone から Mac の監視を開始できます。	iPhone에서 Mac 모니터링을 시작할 수 있습니다。	
在 Mac 端打开设置里的 iOS 远程控制，复制配对信息到这里。TraceFence 不经过云端中继。	Mac の設定で iOS リモート制御を開き、ペアリング情報をコピーしてここに貼り付けます。TraceFence はクラウド中継を使用しません。	Mac 설정에서 iOS 원격 제어를 열고 페어링 정보를 복사해 여기에 붙여 넣으세요. TraceFence는 클라우드 중계를 사용하지 않습니다。	
在本 iOS app 的配对页粘贴并测试。	この iOS App のペアリング画面に貼り付けてテストします。	이 iOS App의 페어링 화면에 붙여 넣고 테스트합니다。	
已从 iPhone 批准 Claude Code 权限请求。	iPhone から Claude Code の権限リクエストを承認しました。	iPhone에서 Claude Code 권한 요청을 승인했습니다。	
已从 iPhone 拒绝 Claude Code 权限请求。	iPhone から Claude Code の権限リクエストを拒否しました。	iPhone에서 Claude Code 권한 요청을 거부했습니다。	
已停止当前 Claude turn，并用新指令继续执行。	現在の Claude ターンを停止し、新しい指示で実行を続行しました。	현재 Claude 턴을 중지하고 새 지시로 실행을 계속했습니다。	
已在 iPhone 上批准 Codex 请求，Mac 任务会继续执行。	iPhone で Codex リクエストを承認しました。Mac のタスクは続行されます。	iPhone에서 Codex 요청을 승인했으며 Mac 작업이 계속 실행됩니다。	
已批准 Agent 请求。	Agent リクエストを承認しました。	Agent 요청을 승인했습니다。	
已拒绝 Agent 请求。	Agent リクエストを拒否しました。	Agent 요청을 거부했습니다。	
已拒绝 Codex 请求。	Codex リクエストを拒否しました。	Codex 요청을 거부했습니다。	
已拒绝 Mac 上的 Codex 请求。	Mac 上の Codex リクエストを拒否しました。	Mac의 Codex 요청을 거부했습니다。	
已检测到 Claude Code CLI，但当前登录无效。请在 Mac 运行 claude auth login；Claude Desktop 与 Claude Code 使用独立登录。	Claude Code CLI を検出しましたが、現在のログインは無効です。Mac で claude auth login を実行してください。Claude Desktop と Claude Code のログインは別です。	Claude Code CLI가 감지되었지만 현재 로그인이 올바르지 않습니다. Mac에서 claude auth login을 실행하세요. Claude Desktop과 Claude Code는 별도로 로그인합니다。	
已确认 Mac 上的 Codex 请求，任务会继续执行。	Mac 上の Codex リクエストを承認しました。タスクは続行されます。	Mac의 Codex 요청을 승인했으며 작업이 계속 실행됩니다。	
应用会请求相机权限用于扫描配对二维码，会请求本地网络权限用于连接同一网络中的 Mac。TraceFence Sentinel 不会出售个人数据。	App はペアリング QR コードのスキャンにカメラ権限、同じネットワーク上の Mac への接続にローカルネットワーク権限を要求します。TraceFence Sentinel は個人データを販売しません。	App은 페어링 QR 코드 스캔을 위해 카메라 권한을, 동일한 네트워크의 Mac 연결을 위해 로컬 네트워크 권한을 요청합니다. TraceFence Sentinel은 개인 데이터를 판매하지 않습니다。	
开启 Mac 本地控制 API，并复制 iOS 配对信息。	Mac のローカル制御 API を有効にし、iOS ペアリング情報をコピーします。	Mac 로컬 제어 API를 켜고 iOS 페어링 정보를 복사합니다。	
我们不会提供云端中转服务。配对信息、访问地址和令牌保存在你的设备上。控制请求只会发送到你配对的 Mac 或你自己配置的网络入口。	クラウド中継サービスは提供しません。ペアリング情報、接続先、トークンはデバイスに保存されます。制御リクエストはペアリングした Mac または自分で設定したネットワーク接続先にのみ送信されます。	클라우드 중계 서비스를 제공하지 않습니다. 페어링 정보, 엔드포인트 및 토큰은 기기에 저장됩니다. 제어 요청은 페어링한 Mac 또는 직접 구성한 네트워크 엔드포인트로만 전송됩니다。	
打开 Mac 版 TraceFence 设置。	Mac 版 TraceFence の設定を開きます。	Mac용 TraceFence 설정을 엽니다。	
指令会发送给会话输入流；Agent 是否立即采纳取决于当前提示状态。	指示はセッションの入力ストリームに送信されます。Agent がすぐに受け入れるかどうかは現在のプロンプト状態によって異なります。	지시는 세션 입력 스트림으로 전송됩니다. Agent가 즉시 반영할지는 현재 프롬프트 상태에 따라 달라집니다。	
指令已交给 Mac 上当前打开的 Codex 会话。	現在 Mac で開いている Codex セッションに指示を送信しました。	현재 Mac에서 열려 있는 Codex 세션에 지시를 보냈습니다。	
指令已发送，Mac 上的 Codex 会话已经开始执行。	指示を送信し、Mac 上の Codex セッションが実行を開始しました。	지시를 보냈으며 Mac의 Codex 세션이 실행을 시작했습니다。	
指令已在真实 Claude Code 后台会话中启动。	実際の Claude Code バックグラウンドセッションで指示を開始しました。	실제 Claude Code 백그라운드 세션에서 지시가 시작되었습니다。	
控制指令已交给 Mac 上的真实 Agent 会话。	Mac 上の実際の Agent セッションに制御指示を送信しました。	Mac의 실제 Agent 세션에 제어 지시를 보냈습니다。	
推荐的互联网远程方案，不需要 TraceFence 后端。	TraceFence バックエンドを必要としない、推奨のインターネット接続方法です。	TraceFence 백엔드가 필요 없는 권장 인터넷 원격 방식입니다。	
推荐的互联网远程方案，不需要 TraceFence 后端；只连接 Mac 一端无法远程访问。	TraceFence バックエンドを必要としない推奨のインターネット接続方法です。Mac 側だけを接続してもリモートアクセスはできません。	TraceFence 백엔드가 필요 없는 권장 인터넷 원격 방식입니다. Mac 쪽만 연결하면 원격으로 접근할 수 없습니다。	
新指令已插入 Mac 上当前打开的 Codex 任务。	Mac で現在開いている Codex タスクに新しい指示を挿入しました。	현재 Mac에서 열려 있는 Codex 작업에 새 지시를 삽입했습니다。	
新指令已插入 Mac 上正在执行的 Codex 任务。	Mac で実行中の Codex タスクに新しい指示を挿入しました。	Mac에서 실행 중인 Codex 작업에 새 지시를 삽입했습니다。	
最简单，适合家里或办公室；离开网络后不可用。	最も簡単な方法で、自宅やオフィスに適しています。そのネットワークから離れると使用できません。	가장 간단하며 집이나 사무실에 적합합니다. 해당 네트워크를 벗어나면 사용할 수 없습니다。	
未安装 Claude Code CLI；Claude Desktop 对话没有开放本地控制 API。	Claude Code CLI がインストールされていません。Claude Desktop のチャットはローカル制御 API を公開していません。	Claude Code CLI가 설치되어 있지 않습니다. Claude Desktop 대화는 로컬 제어 API를 제공하지 않습니다。	
未归类项目	未分類のプロジェクト	분류되지 않은 프로젝트	
正在 Mac 上执行	Mac で実行中	Mac에서 실행 중	
此任务来自日志或数据库快照，TraceFence 没有关联到仍在运行的可控进程。	このタスクはログまたはデータベースのスナップショット由来で、TraceFence は実行中の制御可能なプロセスに関連付けられていません。	이 작업은 로그 또는 데이터베이스 스냅샷에서 가져왔으며 TraceFence가 실행 중인 제어 가능 프로세스와 연결하지 못했습니다。	
此任务来自监控快照，Mac 端没有可控运行时。	このタスクは監視スナップショット由来で、Mac 側に制御可能なランタイムがありません。	이 작업은 모니터링 스냅샷에서 가져왔으며 Mac에 제어 가능한 런타임이 없습니다。	
此设备未启用 Face ID、Touch ID 或设备密码。请先在系统设置中启用设备密码。	このデバイスでは Face ID、Touch ID、デバイスのパスコードが利用できません。先に設定でパスコードを有効にしてください。	이 기기에서 Face ID, Touch ID 또는 기기 암호를 사용할 수 없습니다. 먼저 설정에서 기기 암호를 활성화하세요。	
活跃会话	アクティブなセッション	활성 세션	
点击 Mac 客户端左下角的 iOS 远程配对图标。	Mac クライアント左下の iOS リモートペアリングアイコンをクリックします。	Mac 클라이언트 왼쪽 아래의 iOS 원격 페어링 아이콘을 클릭합니다。	
监控快照不等于可控运行时。	監視スナップショットは制御可能なランタイムではありません。	모니터링 스냅샷은 제어 가능한 런타임이 아닙니다。	
确认 Agent Core 在线，然后复制或显示 iOS 配对信息。	Agent Core がオンラインであることを確認し、iOS ペアリング情報をコピーまたは表示します。	Agent Core가 온라인인지 확인한 뒤 iOS 페어링 정보를 복사하거나 표시합니다。	
等待输入的任务必须有可写入终端才能从 iOS 发送新指令。	入力待ちのタスクに iOS から新しい指示を送るには、書き込み可能なターミナルが必要です。	입력을 기다리는 작업에 iOS에서 새 지시를 보내려면 쓰기 가능한 터미널이 필요합니다。	
要真正发送指令，请使用“接管/启动可控会话”，TraceFence 会创建自己拥有的 CLI/PTY 会话。	実際に指示を送信するには「引き継ぎ／制御セッションを開始」を使用してください。TraceFence が所有する CLI/PTY セッションを作成します。	실제로 지시를 보내려면 ‘인계/제어 세션 시작’을 사용하세요. TraceFence가 소유하는 CLI/PTY 세션을 만듭니다。	
该 Codex 会话当前没有正在执行的任务。	この Codex セッションには現在実行中のタスクがありません。	이 Codex 세션에는 현재 실행 중인 작업이 없습니다。	
该控制只覆盖通过 TraceFence 创建的可控 Agent 会话。	この制御は TraceFence が作成した制御可能な Agent セッションにのみ適用されます。	이 제어는 TraceFence가 만든 제어 가능한 Agent 세션에만 적용됩니다。	
请先打开 Mac 版 TraceFence，再创建或接管新的可控会话。	新しい制御セッションを作成または引き継ぐ前に、Mac 版 TraceFence を開いてください。	새 제어 세션을 만들거나 인계하기 전에 Mac용 TraceFence를 여세요。	
请安装官方独立 Codex CLI 并启动 app-server 服务。	公式のスタンドアロン Codex CLI をインストールし、app-server サービスを起動してください。	공식 독립형 Codex CLI를 설치하고 app-server 서비스를 시작하세요。	
请输入下一步指令；TraceFence 会发送给可控会话，并恢复 Agent 进程组。	次の指示を入力してください。TraceFence が制御セッションに送信し、Agent のプロセスグループを再開します。	다음 지시를 입력하세요. TraceFence가 제어 세션으로 전송하고 Agent 프로세스 그룹을 재개합니다。	
路由器端口转发、防火墙规则、动态域名或固定公网 IP。	ルーターのポート転送、ファイアウォール規則、DDNS、または固定グローバル IP を設定します。	라우터 포트 포워딩, 방화벽 규칙, DDNS 또는 고정 공인 IP를 설정합니다。	
这个任务没有可接管的 Agent 目标。	このタスクには引き継ぎ可能な Agent ターゲットがありません。	이 작업에는 인계할 수 있는 Agent 대상이 없습니다。	
这台 Mac 尚未安装可接管的 CLI Agent。	この Mac には引き継ぎに対応する CLI Agent がインストールされていません。	이 Mac에는 인계할 수 있는 CLI Agent가 설치되어 있지 않습니다。	
这是由 TraceFence 创建的可控 Agent 会话，可被真实暂停、恢复和终止。	これは TraceFence が作成した制御可能な Agent セッションで、実際に一時停止、再開、終了できます。	이 세션은 TraceFence가 만든 제어 가능한 Agent 세션이며 실제로 일시 정지, 재개 및 종료할 수 있습니다。	
进入 TraceFence 订阅里的 iOS 远程控制连接方式。	TraceFence のサブスクリプションにある iOS リモート制御の接続方法を開きます。	TraceFence 구독의 iOS 원격 제어 연결 방식으로 이동합니다。	
进程控制	プロセス制御	프로세스 제어	
进程树控制	プロセスツリー制御	프로세스 트리 제어	
进程组控制	プロセスグループ制御	프로세스 그룹 제어	
远程控制需要 Mac 端有效订阅或试用。	リモート制御には Mac 側で有効なサブスクリプションまたはトライアルが必要です。	원격 제어를 사용하려면 Mac에서 활성 구독 또는 평가판이 필요합니다。	
连接地址	接続先	연결 엔드포인트	
需关注	要確認	주의 필요	
需要 Hook bridge、TraceFence 可控会话或 Agent API 才能插入指令。	指示を挿入するには、Hook bridge、TraceFence の制御セッション、または Agent API が必要です。	지시를 삽입하려면 Hook bridge, TraceFence 제어 세션 또는 Agent API가 필요합니다。	
需要 Hook bridge、TraceFence 可控会话或 Agent API 才能暂停/恢复。	一時停止と再開には、Hook bridge、TraceFence の制御セッション、または Agent API が必要です。	일시 정지 및 재개에는 Hook bridge, TraceFence 제어 세션 또는 Agent API가 필요합니다。	
"""


EXTRA_OVERRIDES = {
    "zh-Hant": {
        "pending": "待處理",
        "running": "執行中",
        "observed": "僅監控",
        "completed": "已完成",
        "interrupted": "已暫停",
        "error": "錯誤",
    },
    "ja": {
        "pending": "保留中",
        "running": "実行中",
        "observed": "監視のみ",
        "completed": "完了",
        "interrupted": "一時停止",
        "error": "エラー",
    },
    "ko": {
        "pending": "대기 중",
        "running": "실행 중",
        "observed": "모니터 전용",
        "completed": "완료",
        "interrupted": "일시 정지",
        "error": "오류",
    },
    "mt": {
        "pending": "Pendenti",
        "running": "Qed Jaħdem",
        "observed": "Monitoraġġ Biss",
        "completed": "Lest",
        "interrupted": "Imwaqqaf",
        "error": "Żball",
    },
}


INFO_VALUES = {
    "en": {
        "NSFaceIDUsageDescription": "TraceFence uses Face ID to protect Mac pairing, agent sessions, approvals, and remote controls.",
        "NSCameraUsageDescription": "TraceFence scans the pairing QR code shown by your Mac.",
        "NSLocalNetworkUsageDescription": "TraceFence connects directly to your Mac on your local network for private remote control.",
    },
    "zh-Hans": {
        "NSFaceIDUsageDescription": "TraceFence 使用面容 ID 保护 Mac 配对、Agent 会话、审批和远程控制。",
        "NSCameraUsageDescription": "TraceFence 用于扫描 Mac 显示的配对二维码。",
        "NSLocalNetworkUsageDescription": "TraceFence 通过本地网络直连你的 Mac，以进行私密远程控制。",
    },
    "zh-Hant": {
        "NSFaceIDUsageDescription": "TraceFence 使用 Face ID 保護 Mac 配對、Agent 工作階段、審批及遠端控制。",
        "NSCameraUsageDescription": "TraceFence 用於掃描 Mac 顯示的配對 QR Code。",
        "NSLocalNetworkUsageDescription": "TraceFence 透過區域網路直接連接你的 Mac，以進行私人遠端控制。",
    },
    "ja": {
        "NSFaceIDUsageDescription": "TraceFence は Face ID を使用して、Mac のペアリング、Agent セッション、承認、リモート操作を保護します。",
        "NSCameraUsageDescription": "TraceFence は Mac に表示されたペアリング QR コードをスキャンします。",
        "NSLocalNetworkUsageDescription": "TraceFence はプライベートなリモート制御のため、ローカルネットワーク上の Mac に直接接続します。",
    },
    "ko": {
        "NSFaceIDUsageDescription": "TraceFence는 Face ID를 사용하여 Mac 페어링, Agent 세션, 승인 및 원격 제어를 보호합니다。",
        "NSCameraUsageDescription": "TraceFence는 Mac에 표시된 페어링 QR 코드를 스캔합니다。",
        "NSLocalNetworkUsageDescription": "TraceFence는 비공개 원격 제어를 위해 로컬 네트워크에서 Mac에 직접 연결합니다。",
    },
    "mt": {
        "NSFaceIDUsageDescription": "TraceFence juża Face ID biex jipproteġi l-pairing tal-Mac, is-sessjonijiet, l-approvazzjonijiet u l-kontrolli remoti.",
        "NSCameraUsageDescription": "TraceFence jiskennja l-kodiċi QR tal-pairing muri mill-Mac tiegħek.",
        "NSLocalNetworkUsageDescription": "TraceFence jikkonnettja direttament mal-Mac fuq in-network lokali għal kontroll remot privat.",
    },
}


def parse_source() -> list[tuple[str, str]]:
    entries: list[tuple[str, str]] = []
    for line_number, line in enumerate(SOURCE.read_text(encoding="utf-8").splitlines(), start=1):
        if not line.strip():
            continue
        match = LINE_PATTERN.match(line)
        if not match:
            raise ValueError(f"Unsupported .strings syntax at {SOURCE}:{line_number}")
        entries.append((json.loads(match.group(1)), json.loads(match.group(2))))
    return entries


def parse_overrides() -> dict[str, dict[str, str]]:
    result = {"ja": {}, "ko": {}, "mt": {}}
    for table_name, table in (
        ("core", TRANSLATIONS),
        ("technical", TECHNICAL_TRANSLATIONS),
    ):
        for line_number, line in enumerate(table.strip("\n").splitlines(), start=1):
            columns = line.split("\t")
            if len(columns) != 4:
                raise ValueError(
                    f"{table_name} translation row {line_number} must have four tab-separated columns"
                )
            key, japanese, korean, maltese = columns
            for language, value in (("ja", japanese), ("ko", korean), ("mt", maltese)):
                if value:
                    result[language][key] = value
    for language, values in EXTRA_OVERRIDES.items():
        result.setdefault(language, {}).update(values)
    return result


def quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def normalize_value(language: str, value: str) -> str:
    if language == "ko":
        return value.translate(str.maketrans({"。": ".", "，": ",", "：": ":", "；": ";"}))
    return value


def write_strings(
    path: Path,
    entries: list[tuple[str, str]],
    values: dict[str, str],
    language: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"{quote(key)} = {quote(normalize_value(language, values.get(key, fallback)))};"
        for key, fallback in entries
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    entries = parse_source()
    keys = {key for key, _ in entries}
    overrides = parse_overrides()
    unknown = sorted({key for values in overrides.values() for key in values if key not in keys})
    if unknown:
        raise ValueError("Translation overrides reference unknown keys: " + ", ".join(unknown))

    traditional = OpenCC("s2twp")
    zh_hant_values = {
        key: traditional.convert(key) if re.search(r"[\u3400-\u9fff]", key) else fallback
        for key, fallback in entries
    }
    zh_hant_values.update(overrides.get("zh-Hant", {}))
    write_strings(
        RESOURCES / "zh-Hant.lproj/Localizable.strings",
        entries,
        zh_hant_values,
        "zh-Hant",
    )

    for language in ("ja", "ko", "mt"):
        write_strings(
            RESOURCES / f"{language}.lproj/Localizable.strings",
            entries,
            overrides.get(language, {}),
            language,
        )

    for language, values in INFO_VALUES.items():
        path = RESOURCES / f"{language}.lproj/InfoPlist.strings"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            "\n".join(
                f"{quote(key)} = {quote(normalize_value(language, value))};"
                for key, value in values.items()
            ) + "\n",
            encoding="utf-8",
        )

    print(f"Generated {len(entries)} keys for zh-Hant, ja, ko, and mt.")


if __name__ == "__main__":
    main()
