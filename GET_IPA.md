# 📦 Как получить IPA файл

## ✅ Изменения отправлены в GitHub!

Ваш код успешно отправлен в репозиторий и GitHub Actions начал сборку.

---

## 🔗 Ссылки

### 1. Проверить статус сборки
👉 **https://github.com/artpm4250-png/olcrtc-ios-client/actions**

### 2. Последний workflow
👉 **https://github.com/artpm4250-png/olcrtc-ios-client/actions/workflows/olcrtc-ios.yml**

### 3. Ваш коммит
👉 **https://github.com/artpm4250-png/olcrtc-ios-client/commit/0467ad9**

---

## ⏱️ Время сборки

Обычно сборка занимает **10-15 минут**:
- ✅ Checkout кода (30 сек)
- ✅ Установка Go и инструментов (2 мин)
- ✅ Сборка Mobile.xcframework (5-7 мин)
- ✅ Генерация Xcode проекта (10 сек)
- ✅ Сборка приложения (2-3 мин)
- ✅ Создание IPA (30 сек)
- ✅ Тесты (1 мин)

---

## 📥 Как скачать IPA

### Способ 1: Через веб-интерфейс

1. Откройте: https://github.com/artpm4250-png/olcrtc-ios-client/actions

2. Найдите последний успешный workflow (зелёная галочка ✅)

3. Кликните на него

4. Прокрутите вниз до секции **Artifacts**

5. Скачайте **OlcRTCClient-unsigned-ipa**

6. Распакуйте ZIP → получите `OlcRTCClient-unsigned.ipa`

### Способ 2: Через GitHub CLI (если установлен)

```bash
# Установите GitHub CLI (если нет)
# https://cli.github.com/

# Скачайте последний artifact
gh run download --repo artpm4250-png/olcrtc-ios-client --name OlcRTCClient-unsigned-ipa
```

---

## 📱 Установка IPA на iPhone

### Вариант 1: ESign (рекомендуется)

1. Скачайте ESign на iPhone
2. Откройте скачанный IPA в ESign
3. Подпишите своим Apple ID
4. Установите на устройство

### Вариант 2: AltStore

1. Установите AltStore на компьютер и iPhone
2. Перетащите IPA в AltStore
3. Приложение установится автоматически

### Вариант 3: Sideloadly

1. Скачайте Sideloadly
2. Подключите iPhone к компьютеру
3. Выберите IPA файл
4. Введите Apple ID
5. Установите

### Вариант 4: Xcode (если есть Mac)

1. Откройте Xcode
2. Window → Devices and Simulators
3. Перетащите IPA на устройство

---

## 🔍 Проверка статуса сборки

### Через браузер

Откройте: https://github.com/artpm4250-png/olcrtc-ios-client/actions

Вы увидите:
- 🟡 **Жёлтый кружок** - сборка в процессе
- ✅ **Зелёная галочка** - сборка успешна
- ❌ **Красный крестик** - ошибка сборки

### Через командную строку

```bash
# Установите GitHub CLI
# https://cli.github.com/

# Проверьте статус последнего workflow
gh run list --repo artpm4250-png/olcrtc-ios-client --limit 1

# Посмотрите логи
gh run view --repo artpm4250-png/olcrtc-ios-client --log
```

---

## 📋 Что включено в IPA

Ваш IPA файл содержит:
- ✨ Все новые улучшения дизайна
- 📳 Haptic feedback
- 💬 Toast-уведомления
- 👆 Swipe-действия
- ⬇️ Pull-to-refresh
- 🎨 Анимации и градиенты
- 🌓 Поддержка Dark Mode

---

## ⚠️ Важно

### Unsigned IPA
IPA файл **не подписан** (unsigned), поэтому:
- ❌ Нельзя установить напрямую через iTunes
- ✅ Нужно подписать через ESign/AltStore/Sideloadly
- ✅ Или использовать Xcode для установки

### Срок действия подписи
При подписи через Free Apple ID:
- ⏱️ Подпись действует **7 дней**
- 🔄 Нужно переподписывать каждую неделю
- 💰 С платным Apple Developer ($99/год) - 1 год

---

## 🐛 Если сборка упала

### Проверьте логи

1. Откройте failed workflow
2. Кликните на красный шаг
3. Посмотрите ошибку

### Частые проблемы

**Go version**
```yaml
# Проверьте, что Go 1.25.x доступен
go-version: "1.25.x"
```

**Mobile.xcframework**
```bash
# Проверьте скрипт сборки
./Scripts/build-mobile-xcframework.sh
```

**Xcode version**
```yaml
# Используется macOS 15 с последним Xcode
runs-on: macos-15
```

---

## 🎉 После установки

1. Откройте приложение
2. Импортируйте профиль
3. Наслаждайтесь новым дизайном!

### Проверьте новые фичи:
- ✨ Пульсирующий статус при подключении
- 📳 Вибрация при нажатии кнопок
- 💬 Toast-уведомления при действиях
- 👆 Swipe профилей влево/вправо
- ⬇️ Pull-to-refresh для обновления

---

## 📞 Нужна помощь?

- 📚 Читайте `QUICK_START.md` для гайда
- 🎨 Смотрите `VISUAL_GUIDE.md` для схем
- 📖 Изучайте `UI_FEATURES.md` для деталей

---

## 🚀 Следующие шаги

1. ⏱️ Подождите 10-15 минут
2. 🔍 Проверьте статус на GitHub Actions
3. 📥 Скачайте IPA из Artifacts
4. 📱 Установите через ESign/AltStore
5. 🎉 Наслаждайтесь!

---

**Ссылка на Actions:** https://github.com/artpm4250-png/olcrtc-ios-client/actions

**Статус:** 🟡 Сборка запущена...
