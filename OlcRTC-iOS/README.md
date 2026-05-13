# OlcRTC iOS Client Starter

Это стартовый iOS-клиент для `olcrtc` в режиме локального SOCKS5-прокси. Он уже содержит:

- SwiftUI-приложение для добавления `olcrtc://` ссылок.
- Парсер URI из `docs/uri.md`.
- Обертку над Go Mobile API `olcrtc/mobile`.
- XcodeGen-конфиг, чтобы быстро собрать проект на macOS.
- GitHub Actions workflow для сборки на macOS runner.

## Важное ограничение

`olcrtc/mobile` запускает локальный SOCKS5-прокси на `127.0.0.1:18080`. Дальше этот прокси нужно указать в Happ, Incy или другом клиенте как outbound/proxy.

Параметры:

- Type: `SOCKS5`
- Host: `127.0.0.1`
- Port: `18080`
- Auth: off

Без `NetworkExtension` это не системный VPN: Safari и большинство приложений iOS не будут автоматически использовать этот SOCKS. Такой режим полезен именно как приложение-компаньон для клиентов, которые умеют ходить через локальный SOCKS.

Еще один iOS-нюанс: без `NetworkExtension` система может приостановить процесс в фоне, и тогда Happ/Incy потеряет локальный SOCKS. В приложении включен silent audio keep-alive через `UIBackgroundModes: audio`, чтобы процесс продолжал жить после переключения в Happ/Incy.

Приложение отслеживает смену сети через `NWPathMonitor`. При переходе Wi-Fi -> LTE или LTE -> Wi-Fi оно ждет, пока iOS снова отдаст рабочий сетевой путь, затем автоматически перезапускает текущую `olcrtc`-сессию. Если Happ/Incy уже успел пометить старое соединение как ошибочное, нажми `Reconnect` в OlcRTC и переподключи профиль в Happ/Incy.

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
