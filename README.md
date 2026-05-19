# OlcRTC Gateway for iOS

[![OlcRTC iOS](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml/badge.svg)](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml)

Нативный iOS-клиент для `olcrtc`: локальный SOCKS5 для Happ и других клиентов,
системный `NetworkExtension` профиль, packet tunnel через tun2socks и аккуратный
split-routing для локальных сетей.

## Возможности

- Импорт `olcrtc://` ссылок, pasted `sub.md` подписок и HTTP/HTTPS subscription URL.
- Локальный SOCKS5 с авторизацией и готовыми `socks://` / `socks5://` ссылками.
- Хранение SOCKS-секретов и ключей профилей в iOS Keychain.
- Автоподбор свободного SOCKS-порта и проверка реального SOCKS `CONNECT`.
- Watchdog, диагностика, лог событий, ping профиля до Google.
- Silent audio keep-alive для более живучей работы локального SOCKS в фоне.
- Поддержка `jitsi`, `telemost`, `wbstream`, `jazz` из `olcrtc@refactor/universal-carrier`.
- URI payload для `vp8channel`, `seichannel`, `videochannel`.
- Системный `PacketTunnelProvider` без Happ.
- Packet mode через `Tun2SocksKit`: весь трафик или split-routing.
- Unsigned IPA сборка через GitHub Actions для подписи через ESign.

## Режимы

| Режим | Для чего | Как работает |
| --- | --- | --- |
| Локальный SOCKS | Happ / внешний клиент | Приложение держит `127.0.0.1:<port>` и отдаёт SOCKS5 credentials |
| Прокси | Быстрый системный режим | iOS PAC отправляет HTTP/HTTPS через локальный SOCKS |
| Весь | Полный системный туннель | Default route через `Tun2SocksKit` в локальный SOCKS `olcrtc` |
| Раздельно | VPN без локальных сетей | Default route через tun2socks, private/local CIDR идут напрямую |

В split-routing исключены `10/8`, `100.64/10`, `127/8`, `169.254/16`,
`172.16/12`, `192.168/16` и multicast.

## Быстрый старт

1. Скачай последний artifact `OlcRTCClient-unsigned-ipa` из GitHub Actions.
2. Подпиши `OlcRTCClient-unsigned.ipa` через ESign.
3. Импортируй `olcrtc://` ссылку или подписку.
4. Для Happ запусти локальный SOCKS и скопируй `socks://` / `socks5://`.
5. Для режима без Happ установи системный VPN профиль и выбери `Прокси`, `Весь`
   или `Раздельно`.

## Локальный SOCKS

- Host: `127.0.0.1`
- Port: показывается в приложении, обычно `18080`
- Auth: `On`
- Username/Password: генерируются приложением и хранятся в Keychain

Если порт занят, приложение выберет следующий свободный и покажет его в карточке
локального прокси.

## olcRTC URI

Актуальный upstream-формат не содержит обязательный `client_id`:

```text
olcrtc://<auth>?<transport>@<room>#<64-hex-key>$<name>
```

Пример Jitsi datachannel:

```text
olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/myroom#37ab424e157dd43204640bd098196e415ce3676c039e5ba6b2847d54cbe26745$Jitsi data
```

Технический `device_id` создаётся приложением отдельно для каждой установки, так
что одну и ту же ссылку можно давать разным людям.

## Сборка

Workflow `.github/workflows/olcrtc-ios.yml` делает:

- сборку `Mobile.xcframework` из `openlibrecommunity/olcrtc@refactor/universal-carrier`;
- применение compatibility patches из `OlcRTC-iOS/Patches`;
- генерацию Xcode project через XcodeGen;
- сборку simulator app;
- сборку unsigned device app;
- упаковку unsigned IPA;
- запуск unit-тестов URI/SOCKS/subscription.

## Структура

- `OlcRTC-iOS/Sources/OlcRTCApp` - SwiftUI-приложение.
- `OlcRTC-iOS/Sources/OlcRTCPacketTunnel` - системный Packet Tunnel extension.
- `OlcRTC-iOS/Tests/OlcRTCAppTests` - тесты URI, SOCKS-ссылок и подписок.
- `OlcRTC-iOS/Patches` - патчи совместимости для актуального upstream `olcrtc`.
- `OlcRTC-iOS/Scripts` - сборка gomobile framework и unsigned IPA.
- `.github/workflows/olcrtc-ios.yml` - macOS CI, сборка IPA и тесты.

## Источники

- [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc)
- [olcrtc URI format](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md)
- [Tun2SocksKit](https://github.com/EbrahimTahernejad/Tun2SocksKit)
- [plumbicon/olcrtc-call](https://github.com/plumbicon/olcrtc-call)
