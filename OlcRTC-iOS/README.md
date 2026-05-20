# OlcRTC Gateway iOS

Это iOS-клиент для `olcrtc` в режиме локального SOCKS5-прокси. Он уже содержит:

- SwiftUI-приложение для добавления `olcrtc://` ссылок.
- Импорт pasted `sub.md` подписок и HTTP/HTTPS URL подписок.
- Парсер URI из `docs/uri.md`.
- Обертку над Go Mobile API `olcrtc/mobile`.
- Хранение SOCKS-секретов и ключей профилей в Keychain.
- Авто-подбор свободного SOCKS-порта.
- Поддержку актуального `jitsi` carrier и URI payload из ветки `refactor/universal-carrier`.
- XcodeGen-конфиг, чтобы быстро собрать проект на macOS.
- GitHub Actions workflow для сборки на macOS runner.
- `NetworkExtension` target `OlcRTCPacketTunnel` для системного VPN-профиля.
- `Tun2SocksKit` для packet tunnel режима `Весь` и `Локальные`.

## Важное ограничение

`olcrtc/mobile` запускает локальный SOCKS5-прокси на `127.0.0.1`. Обычно используется порт `18080`, но если он занят, приложение само выберет следующий свободный порт. Дальше этот прокси нужно указать во внешнем VPN-клиенте как outbound/proxy.

Параметры:

- Type: `SOCKS5`
- Host: `127.0.0.1`
- Port: смотри в карточке `Локальный прокси`
- Auth: on
- Username/Password: генерируются приложением при первом запуске и хранятся в Keychain

Ключи `olcrtc://` профилей тоже сохраняются в Keychain. В `UserDefaults` остается только публичная часть профиля.

В приложении теперь есть два режима:

- `Локальный прокси` - старый совместимый SOCKS5 режим для внешних клиентов.
- `Системный VPN` - iOS `PacketTunnelProvider`, который запускает olcRTC внутри VPN extension, дожидается готовности SOCKS и работает как full packet tunnel или туннель с исключением локальных сетей.

Режимы:

- `Весь` - default route через `Tun2SocksKit`, дальше в локальный SOCKS `olcrtc`.
- `Локальные` - default route через `Tun2SocksKit`, но private/local сети исключены из туннеля.

Важно: `Локальные` - это базовый split только по CIDR локальных сетей. Правила
вида `geosite:*`, `geoip:*`, `direct/proxy/block` текущий `Tun2SocksKit` слой не
исполняет сам по себе. Для такого роутинга нужен embedded routing engine уровня
Xray/sing-box или отдельный маршрутизатор перед SOCKS.

В приложении уже заведены пресеты маршрутизации:

- `Весь трафик` - final outbound через `olcrtc`.
- `Simple-RU` - RU/private/Apple напрямую, YouTube/category-ban-ru через `olcrtc`.
- `Только блокировки` - выбранные geosite-правила через `olcrtc`, остальное напрямую.
- `Локальные мимо` - только private/local сети напрямую.

Для этих пресетов есть генератор sing-box JSON: inbound `tun`, outbound `socks`
на локальный `olcrtc`, `direct`, `block` и remote rule-set. `Libbox.xcframework`
подключается только к Packet Tunnel extension; основной app bundle его не
встраивает, чтобы не ломать установку приложения на симуляторе/iOS.

Еще один iOS-нюанс: без `NetworkExtension` система может приостановить процесс в фоне, и тогда внешний клиент потеряет локальный SOCKS. В приложении включен silent audio keep-alive через `UIBackgroundModes: audio`, чтобы процесс продолжал жить после переключения во внешний VPN-клиент.

Важно: когда внешний VPN-клиент уже поднял туннель через локальный SOCKS, при смене Wi-Fi -> LTE или LTE -> Wi-Fi может появиться петля маршрутизации. `olcrtc` пытается переподключиться, но его собственный трафик уходит в уже сломанный туннель внешнего клиента. Поэтому приложение не обещает бесшовный reconnect в этой схеме. При смене сети оно показывает состояние `Нужен рестарт VPN`: выключи туннель во внешнем клиенте, нажми `Перезапустить` в OlcRTC, затем включи туннель обратно.

В интерфейсе есть карточка текущего состояния, активная сеть, счетчик перезапусков, импорт из буфера обмена, открытие `olcrtc://` ссылок, импорт pasted `sub.md` подписок, импорт URL подписок, быстрое копирование SOCKS-параметров и готовые ссылки `socks://` / `socks5://` для импорта во внешний клиент.

В приложение добавлен watchdog локального SOCKS. Через 20 секунд после запуска, а затем примерно раз в 45 секунд, он проверяет не просто открытый TCP-порт, а полноценный SOCKS5 `CONNECT` через туннель. Проба идет по нескольким целям, чтобы одна недоступная точка не давала ложную ошибку. Если проверка два раза подряд не проходит, приложение пишет событие в журнал и перезапускает `olcrtc`. Это помогает при сценарии, когда через долгое время умирает именно локальный SOCKS-процесс или сам маршрут через него.

В разделе `Диагностика` можно скопировать последние события: запуск, остановку, смену сети, проверки watchdog и ошибки запуска.

Packet режим требует успешной линковки `Tun2SocksKit` в extension. Если пакет не собран, приложение покажет ошибку `Tun2SocksKit is not linked to the packet tunnel`.

## Структура

- `project.yml` - XcodeGen-проект.
- `Sources/OlcRTCApp` - основное iOS-приложение.
- `Sources/OlcRTCPacketTunnel` - iOS Packet Tunnel extension.
- `Tests/OlcRTCAppTests` - тесты парсера URI.
- `Scripts/build-mobile-xcframework.sh` - сборка Go Mobile framework из `openlibrecommunity/olcrtc`.
- `.github/workflows/olcrtc-ios.yml` - сборка через GitHub Actions.

## Как собрать на Mac

1. Установить Xcode, Go и XcodeGen.

```bash
brew install go xcodegen
go install golang.org/x/mobile/cmd/gomobile@latest
gomobile init
```

2. Собрать Go Mobile framework:

```bash
cd OlcRTC-iOS
./Scripts/build-mobile-xcframework.sh
```

3. Сгенерировать Xcode-проект:

```bash
xcodegen generate
open OlcRTCClient.xcodeproj
```

4. Запустить на iPhone или симуляторе. Для установки на реальный iPhone все равно понадобится подпись Apple Developer.

## Как собрать через GitHub Actions

Workflow уже лежит в `.github/workflows/olcrtc-ios.yml`.

Он делает:

- устанавливает `xcodegen` и `gomobile`;
- собирает `Mobile.xcframework`;
- генерирует `OlcRTCClient.xcodeproj`;
- собирает приложение под iOS Simulator без подписи;
- собирает unsigned `.app` под настоящий iPhone;
- упаковывает unsigned `.ipa` для подписи через ESign;
- запускает тесты парсера URI.

После успешного workflow скачай artifact `OlcRTCClient-unsigned-ipa`. Внутри будет:

```text
OlcRTCClient-unsigned.ipa
```

Этот файл можно подписывать через ESign. Без подписи iPhone его не установит.

## Jitsi

Для Jitsi используется carrier `jitsi` и transport `datachannel`. В поле room
передается полный URL комнаты:

```text
olcrtc://jitsi?datachannel@https://meet.cryptopro.ru/myroom#37ab424e157dd43204640bd098196e415ce3676c039e5ba6b2847d54cbe26745$Jitsi data
```

Скрипт `Scripts/build-mobile-xcframework.sh` по умолчанию собирает
`openlibrecommunity/olcrtc` из ветки `refactor/universal-carrier`, где этот
carrier уже есть. Client ID в ссылке больше не нужен: приложение само создает внутренний технический device_id, уникальный для каждой установки на iPhone. Старый формат с %clientID пока принимается только для совместимости. При необходимости ветку можно переопределить переменной
`OLCRTC_REF`.

## Проверочная ссылка

Можно вставить такую строку в поле импорта:

```text
olcrtc://wbstream?datachannel@019e1c7c-daee-7747-b14b-8a5e7c950da5#37ab424e157dd43204640bd098196e415ce3676c039e5ba6b2847d54cbe26745$olc datachannel
```

## Источники

- https://github.com/openlibrecommunity/olcrtc
- https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md
- https://github.com/openlibrecommunity/olcrtc/blob/master/docs/settings.md
- https://github.com/openlibrecommunity/olcrtc/blob/master/mobile/mobile.go
