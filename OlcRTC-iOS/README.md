# OlcRTC iOS Client Starter

Это стартовый iOS-клиент для `olcrtc` в режиме локального SOCKS5-прокси. Он уже содержит:

- SwiftUI-приложение для добавления `olcrtc://` ссылок.
- Парсер URI из `docs/uri.md`.
- Обертку над Go Mobile API `olcrtc/mobile`.
- XcodeGen-конфиг, чтобы быстро собрать проект на macOS.
- GitHub Actions workflow для сборки на macOS runner.

## Важное ограничение

`olcrtc/mobile` запускает локальный SOCKS5-прокси на `127.0.0.1:18080`. Дальше этот прокси нужно указать во внешнем VPN-клиенте как outbound/proxy.

Параметры:

- Type: `SOCKS5`
- Host: `127.0.0.1`
- Port: `18080`
- Auth: on
- Username/Password: генерируются приложением при первом запуске

Без `NetworkExtension` это не системный VPN: Safari и большинство приложений iOS не будут автоматически использовать этот SOCKS. Такой режим полезен именно как приложение-компаньон для клиентов, которые умеют ходить через локальный SOCKS.

Еще один iOS-нюанс: без `NetworkExtension` система может приостановить процесс в фоне, и тогда внешний клиент потеряет локальный SOCKS. В приложении включен silent audio keep-alive через `UIBackgroundModes: audio`, чтобы процесс продолжал жить после переключения во внешний VPN-клиент.

Важно: когда внешний VPN-клиент уже поднял туннель через локальный SOCKS, при смене Wi-Fi -> LTE или LTE -> Wi-Fi может появиться петля маршрутизации. `olcrtc` пытается переподключиться, но его собственный трафик уходит в уже сломанный туннель внешнего клиента. Поэтому приложение не обещает бесшовный reconnect в этой схеме. При смене сети оно показывает состояние `Нужен рестарт VPN`: выключи туннель во внешнем клиенте, нажми `Restart SOCKS` в OlcRTC, затем включи туннель обратно.

В интерфейсе есть карточка текущего состояния, активная сеть, счетчик перезапусков, импорт из буфера обмена, открытие `olcrtc://` ссылок, быстрое копирование SOCKS-параметров и готовые ссылки `socks://` / `socks5://` для импорта во внешний клиент.

В приложение добавлен watchdog локального SOCKS. Через 20 секунд после запуска, а затем примерно раз в 45 секунд, он проверяет не просто открытый TCP-порт, а полноценный SOCKS5 auth-handshake с текущими логином и паролем. Если проверка два раза подряд не проходит, приложение пишет событие в журнал и перезапускает `olcrtc`. Это помогает при сценарии, когда через долгое время умирает именно локальный SOCKS-процесс. Если проблема в том, что внешний VPN-клиент держит сломанный системный туннель после смены сети, watchdog покажет это в диагностике, но не сможет обойти маршрутизационную петлю без `NetworkExtension`.

В разделе `Диагностика` можно скопировать последние события: запуск, остановку, смену сети, проверки watchdog и ошибки запуска.

Для полноценного "VPN для всего iPhone" позже нужен `PacketTunnelProvider` плюс `tun2socks`, который будет читать пакеты из `NEPacketTunnelFlow` и отправлять их в локальный SOCKS5 `olcrtc`.

## Структура

- `project.yml` - XcodeGen-проект.
- `Sources/OlcRTCApp` - основное iOS-приложение.
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

## Проверочная ссылка

Можно вставить такую строку в поле импорта:

```text
olcrtc://wbstream?datachannel@019e1c7c-daee-7747-b14b-8a5e7c950da5#37ab424e157dd43204640bd098196e415ce3676c039e5ba6b2847d54cbe26745%device3$olc datachannel device3
```

## Источники

- https://github.com/openlibrecommunity/olcrtc
- https://github.com/openlibrecommunity/olcrtc/blob/master/docs/uri.md
- https://github.com/openlibrecommunity/olcrtc/blob/master/docs/settings.md
- https://github.com/openlibrecommunity/olcrtc/blob/master/mobile/mobile.go
