# OlcRTC Gateway for iOS

[![OlcRTC iOS](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml/badge.svg)](https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml)

Нативный iOS-клиент для `olcrtc`: локальный SOCKS5 для Happ и других клиентов,
системный `NetworkExtension` профиль и packet tunnel через tun2socks. Текущий
`Локальные` режим исключает только private/local CIDR; rule-based routing уровня
`geosite`/`geoip` требует отдельного routing engine.

> Проект ориентирован на сборку unsigned IPA через GitHub Actions и последующую
> подпись пользователем через ESign, AltStore, SideStore или другой личный способ.

## Статус

| Компонент | Состояние |
| --- | --- |
| Локальный SOCKS5 | Работает, есть авторизация и проверка handshake |
| Импорт подписок | `olcrtc://`, plain text, `sub.md`, HTTP/HTTPS URL |
| System VPN | Есть `NetworkExtension PacketTunnelProvider` |
| Полный туннель | Через `Tun2SocksKit` в локальный SOCKS |
| Локальные сети мимо VPN | Private/local CIDR исключены из туннеля |
| Upstream olcRTC | Сборка подтягивает `refactor/universal-carrier` |
| IPA | Собирается workflow `OlcRTC iOS` |

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
- Packet mode через `Tun2SocksKit`: весь трафик или local/private CIDR мимо VPN.
- Пресеты маршрутизации для будущего rule engine: `Simple-RU`, `Только блокировки`,
  `Весь трафик`, `Локальные мимо`.
- Unsigned IPA сборка через GitHub Actions для подписи через ESign.

## Режимы

| Режим | Для чего | Как работает |
| --- | --- | --- |
| Локальный SOCKS | Happ / внешний клиент | Приложение держит `127.0.0.1:<port>` и отдаёт SOCKS5 credentials |
| Весь | Полный системный туннель | Default route через `Tun2SocksKit` в локальный SOCKS `olcrtc` |
| Локальные | VPN без локальных сетей | Default route через tun2socks, private/local CIDR идут напрямую |

В режиме `Локальные` исключены `10/8`, `100.64/10`, `127/8`, `169.254/16`,
`172.16/12`, `192.168/16` и multicast.

Это не полноценная маршрутизация по `geosite`/`geoip`. Для правил вида
`geosite:youtube -> proxy`, `geoip:ru -> direct`, `category-ru -> direct`
нужен embedded router уровня Xray/sing-box или отдельный routing слой перед SOCKS.
В коде уже есть модель пресетов и генератор sing-box JSON, который подключается
к outbound `socks -> 127.0.0.1:<olcrtc_port>`.

## Быстрый старт

1. Скачай последний artifact `OlcRTCClient-unsigned-ipa` из GitHub Actions.
2. Подпиши `OlcRTCClient-unsigned.ipa` через ESign.
3. Импортируй `olcrtc://` ссылку или подписку.
4. Для Happ запусти локальный SOCKS и скопируй `socks://` / `socks5://`.
5. Для режима без Happ включи `Системный VPN` и выбери `Весь` или `Локальные`.

## Для тестировщиков

При баг-репорте лучше сразу приложить:

- версию iOS и модель устройства;
- carrier/provider и тип сети: Wi-Fi, LTE, 5G;
- режим приложения: локальный SOCKS, Весь или Локальные;
- транспорт `olcrtc`: `datachannel`, `vp8channel`, `seichannel`, `videochannel`;
- последние 30-50 строк лога из приложения без приватных ключей.

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

## Документы

- [Как получить IPA](GET_IPA.md)
- [Короткий старт](QUICK_START.md)
- [Что уже сделано](WHATS_DONE.md)
- [План улучшений](FUTURE_IMPROVEMENTS.md)
- [Разбор кода](CODE_ANALYSIS.md)
- [Заметки по дизайну](DESIGN_IMPROVEMENTS.md)

## Вклад в проект

Смотри [CONTRIBUTING.md](CONTRIBUTING.md). Для ошибок используй GitHub Issues:
так проще не потерять устройство, сеть, профиль и логи.

## Источники

- [openlibrecommunity/olcrtc](https://github.com/openlibrecommunity/olcrtc)
- [olcrtc URI format](https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md)
- [Tun2SocksKit](https://github.com/EbrahimTahernejad/Tun2SocksKit)
- [plumbicon/olcrtc-call](https://github.com/plumbicon/olcrtc-call)
