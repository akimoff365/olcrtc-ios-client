# Как помогать проекту

Спасибо за интерес к `OlcRTC Gateway for iOS`. Проект пока быстро меняется,
поэтому самый полезный вклад - понятные баг-репорты, проверка сборок на реальных
iPhone и небольшие точечные pull request.

## Перед pull request

1. Проверь, что изменение относится к iOS-клиенту, сборке IPA или совместимости
   с `openlibrecommunity/olcrtc`.
2. Не добавляй приватные ссылки, ключи, комнаты, IP-адреса и логи с секретами.
3. Для UI-изменений приложи скриншоты.
4. Для сетевых фиксов укажи, какой режим проверялся: локальный SOCKS, Прокси,
   Весь или Раздельно.

## Локальная структура

- `OlcRTC-iOS/Sources/OlcRTCApp` - приложение и интерфейс.
- `OlcRTC-iOS/Sources/OlcRTCPacketTunnel` - системный VPN extension.
- `OlcRTC-iOS/Tests/OlcRTCAppTests` - unit-тесты.
- `OlcRTC-iOS/Patches` - патчи для актуального upstream `olcrtc`.

## Проверки

Минимум перед PR:

```bash
cd OlcRTC-iOS
xcodegen generate
xcodebuild -project OlcRTCClient.xcodeproj -scheme OlcRTCAppTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

Если изменение касается IPA или `Mobile.xcframework`, лучше дополнительно
запустить GitHub Actions workflow `OlcRTC iOS`.

## Стиль

- Текст в приложении и GitHub-документации пишем по-русски.
- Swift-код держим простым: меньше магии, больше явных состояний.
- Секреты профилей и SOCKS должны храниться в Keychain.
- Любая новая сетевая логика должна писать понятные логи без раскрытия ключей.
