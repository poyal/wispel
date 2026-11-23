# Wispel 전달 규약

한 설치에서 발신 기기는 여러 대, 현재 수신기는 한 대입니다. 서버 주소와 TLS 인증서 SHA-256 지문은 일회용 QR에 함께 들어갑니다. 최초 등록부터 이 지문과 호스트를 검증합니다. 등록 후에는 서버가 발급한 기기별 Bearer 자격을 HTTPS 또는 WSS로 전송합니다.

| 인터페이스 | 입력 및 결과 |
|---|---|
| `POST /v1/pair` | 일회용 `code`, `platform`(ios/android), 표시용 `name`을 받습니다. 성공하면 id·name·platform·role·token을 돌려줍니다. 역할은 운영 CLI가 정합니다. |
| `GET /v1/devices` | 등록된 기기의 id·name·platform·role을 조회합니다. |
| `PUT /v1/devices/{id}`, `DELETE /v1/devices/{id}` | 이름을 변경하거나 연결을 해제합니다. 서브폰은 자기 기기, 현재 본폰은 등록 기기를 관리합니다. |
| `POST /v1/events` | eventId(UUID), sourceId, kind, occurredAt(UTC Unix 밀리초)만 받습니다. 같은 ID·내용은 기존 접수이며, 내용이 다른 재사용은 409입니다. 기기 인증은 401, 역할·발신기 불일치는 403입니다. |
| `GET /v1/stream` | 등록된 안드로이드 본폰이 WebSocket으로 업그레이드합니다. 각 JSON 메시지는 이벤트 네 필드와 sourceName을 담습니다. |
| `POST /v1/ack` | 본폰이 sourceId와 eventId로 처리 결과를 확인합니다. 중복 확인은 같은 이벤트에 적용합니다. |
| `PUT /v1/apns` | iOS 본폰이 value 필드에 기기 토큰을 등록합니다. 새 본폰이 준비되면 이전 본폰으로 향하는 미발송 건을 취소합니다. |

종류는 `call`, `missedCall`, `sms`, `slack`, `mail`, `kakao`입니다. 연락처·번호·본문은 발신 기기에만 머뭅니다. 발생 후 24시간이 지나면 만료되고 운영 기록은 접수 후 7일에 정리합니다. 안드로이드에 다시 보낼 때 같은 ID를 사용합니다. APNs의 성공 응답은 시스템의 접수이며, iOS 앱이 관찰한 수신 확인은 별도 상태입니다.

직접 수신 서비스는 사용자가 켜며 중지 동작을 갖춘 상태 알림을 표시합니다. 절전·네트워크 단절로 도착이 늦어지면 다음 연결 때 대기 중인 이벤트를 처리합니다. 운영 점검은 Windows의 ACL로 보호한 명명된 파이프와 별도 루프백 웹에서 수행합니다.
