# OlcRTC Gateway for iOS

[![OlcRTC iOS](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml/badge.svg)](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml)

Нативный iOS-клиент-компаньон для `olcrtc`. Приложение поднимает локальный
SOCKS5-прокси на iPhone, а внешний VPN-клиент подключается к нему через
`127.0.0.1`.

## Что умеет

- импорт одной `olcrtc://` ссылки;
- импорт pasted `sub.md` подписки с несколькими узлами;
- импорт HTTP/HTTPS URL подписки;
- SOCKS5 auth и готовые `socks://` / `socks5://` ссылки для внешнего клиента;
- хранение SOCKS-секретов и ключей профилей в iOS Keychain;
- автоматический подбор свободного локального SOCKS-порта;
- проверка не только открытого порта, а реального SOCKS `CONNECT`;
- watchdog, диагностика и копирование лога;
- silent audio keep-alive для более стабильной работы в фоне;
- поддержка `jitsi`, `telemost`, `wbstream` и `jazz` из актуальной ветки `olcrtc`;
- unsigned IPA сборка через GitHub Actions для подписи через ESign.

## Важное ограничение

Это не `NetworkExtension`-VPN. Приложение поднимает локальный SOCKS, а системный
туннель делает внешний клиент. При смене Wi-Fi/LTE внешний туннель может держать
сломанный маршрут. В таком случае выключи внешний VPN-клиент, нажми
`Перезапустить` в OlcRTC Gateway и включи внешний туннель снова.

## Быстрый старт

1. Скачай последний artifact `OlcRTCClient-unsigned-ipa` из GitHub Actions.
2. Подпиши `OlcRTCClient-unsigned.ipa` через ESign.
3. Импортируй `olcrtc://` ссылку или подписку в приложении.
4. Запусти профиль в OlcRTC Gateway.
5. Скопируй `socks://` или `socks5://` ссылку во внешний VPN-клиент.

## Локальный SOCKS

- Host: `127.0.0.1`
- Port: показывается в приложении, обычно `18080`
- Auth: `On`
- Username/Password: генерируются приложением и хранятся в Keychain

Ключи `olcrtc://` профилей тоже сохраняются в Keychain. В `UserDefaults`
остаётся только публичная часть профиля.

Если порт занят, приложение выберет следующий свободный и покажет новый порт в
карточке локального прокси.

## Jitsi

Сборка Mobile framework закреплена на ветке
`openlibrecommunity/olcrtc@refactor/universal-carrier`, где добавлен carrier
`jitsi`. Для Jitsi используем `datachannel`, а в `room` передаём полный URL
комнаты:

```text
olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/myroom#<64-hex-key>$Jitsi data
```

Новый URI-формат upstream не содержит `client-id`. Приложение генерирует
технический `device_id` само и передаёт его только в mobile API `olcrtc`.

## Структура

- `OlcRTC-iOS/Sources/OlcRTCApp` - SwiftUI-приложение.
- `OlcRTC-iOS/Tests/OlcRTCAppTests` - тесты URI, SOCKS-ссылок и подписок.
- `OlcRTC-iOS/Scripts` - сборка gomobile framework и unsigned IPA.
- `.github/workflows/olcrtc-ios.yml` - macOS CI, сборка IPA и тесты.

## Источники

- [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc)
- [olcrtc URI format](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md)
- [plumbicon/olcrtc-call](https://github.com/plumbicon/olcrtc-call)
