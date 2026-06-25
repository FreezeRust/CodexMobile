# 📱 Codex Mobile

Codex прямо на iPhone: вход в свой аккаунт Codex, проекты и чаты, генерация
файлов через ИИ и подключение любых нейросетей по API.

## Что умеет

| Функция | Где |
|---|---|
| 🔐 **Вход в Codex** | Вкладка **Codex** — встроенная страница входа ChatGPT/Codex (`WKWebView`). Сессия сохраняется между запусками. |
| 📁 **Проекты** | Вкладка **Проекты** — создавай проекты, внутри них чаты и файлы. |
| 💬 **Чаты с ИИ** | Внутри проекта — чат с потоковым ответом (streaming). |
| 📄 **Генерация файлов** | Блоки кода из ответов ИИ автоматически становятся файлами проекта. Любой файл можно **«отдать»** через системный share-лист (AirDrop, Файлы, мессенджеры). |
| 🧠 **Добавление нейросетей** | Вкладка **Нейросети** — добавляй любой OpenAI-совместимый API (OpenAI, локальные модели, прокси): название, Base URL, модель, ключ. Ключи хранятся в Keychain. |

> ⚠️ **Про «компиляцию на телефоне»:** iOS запрещает запуск произвольного
> скомпилированного кода в обычном приложении (sandbox). Поэтому приложение
> работает по выбранной тобой схеме «ИИ генерирует код и файлы» — ИИ пишет/правит
> файлы, ты их просматриваешь и экспортируешь. Реальную компиляцию можно добавить
> позже через удалённый сервер сборки (раздел «Дальше» ниже).

---

## 🚀 Как получить .ipa без Mac (через GitHub + SideStore)

У тебя есть сертификат и SideStore — значит подпись сделает сам SideStore.
Нам нужен **неподписанный .ipa**, который соберёт GitHub бесплатно.

1. Создай репозиторий на GitHub и залей туда папку `CodexMobile`.
   ```bash
   cd CodexMobile
   git init
   git add .
   git commit -m "Codex Mobile"
   git branch -M main
   git remote add origin https://github.com/ТВОЙ_ЛОГИН/CodexMobile.git
   git push -u origin main
   ```
2. Открой вкладку **Actions** в репозитории. Workflow **«Build unsigned IPA»**
   запустится автоматически (или нажми *Run workflow*).
3. Дождись зелёной галочки → внизу страницы запуска раздел **Artifacts** →
   скачай `CodexMobile-unsigned-ipa` (это zip с `CodexMobile.ipa` внутри).
4. Распакуй zip, получишь `CodexMobile.ipa`.
5. Открой **SideStore** на iPhone → **+** → выбери `CodexMobile.ipa`.
   SideStore подпишет его твоим сертификатом и установит. Готово ✅

### Альтернатива: сборка на своём Mac
```bash
cd CodexMobile
brew install xcodegen
xcodegen generate
open CodexMobile.xcodeproj
```
Далее в Xcode: *Product → Archive → Distribute → Ad Hoc / Development*, либо
собери `.app` и заархивируй в `.ipa` вручную (см. шаги в workflow).

---

## 🗂 Структура

```
CodexMobile/
├── project.yml                  # описание проекта для XcodeGen
├── .github/workflows/
│   └── build-ipa.yml            # автосборка неподписанного .ipa
└── Sources/
    ├── App/
    │   ├── CodexMobileApp.swift  # точка входа
    │   └── Info.plist
    ├── Models/Models.swift       # Project, Chat, Message, AIProvider, GeneratedFile
    ├── Services/
    │   ├── AIClient.swift        # streaming к OpenAI-совместимому API + извлечение файлов
    │   └── KeychainService.swift # хранение ключей
    ├── Stores/Stores.swift       # AppStore, SettingsStore, SessionStore
    └── Views/
        ├── RootView.swift
        ├── CodexWebView.swift    # вход в Codex
        ├── ProjectsView.swift
        ├── ProjectDetailView.swift
        ├── ChatView.swift
        ├── FileDetailView.swift  # просмотр и экспорт файлов
        └── SettingsView.swift    # добавление нейросетей
```

---

## ▶️ Первый запуск
1. Вкладка **Нейросети** → **+** → добавь провайдера и API-ключ
   (для Codex/OpenAI: Base URL `https://api.openai.com/v1`, модель напр. `gpt-4o-mini`).
2. Вкладка **Codex** → войди в свой аккаунт (для работы с веб-Codex).
3. Вкладка **Проекты** → создай проект → создай чат → пиши запросы.
   Код из ответов сам станет файлами проекта, которые можно экспортировать.

---

## 🔭 Дальше (опционально)
- **Реальная компиляция:** поднять сервер (Docker) с тулчейнами; приложение
  отправляет файлы → сервер компилирует → возвращает бинарь/логи. Архитектура
  под это уже готова (`AIClient` легко расширить вторым endpoint'ом).
- **Импорт cookie Codex в API-режим** для бесшовной авторизации.
