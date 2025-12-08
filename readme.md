# service-discovery + worker

Монорепозиторий содержит два связанных проекта:

- **service-discovery** — реестр/диспетчер сервисов на C++.
- **worker** — простой C++-сервис, который запускается внутри контейнера с `systemd`, регистрируется в discovery и шлёт heartbeat по таймеру.

---

## Структура репозитория

Cтруктура:

```text
.
├── discovery/          # сервис service-discovery
└── worker/             # worker-сервис (контейнер с systemd)
```
