# Service Discovery

Небольшой сервис на C++, который выполняет роль **реестра и discovery-сервиса** для контейнеров/сервисов:

- принимает регистрацию/heartbeat сервисов (`/register`);
- хранит список живых сервисов с их состоянием (`/services`);
- имеет простой health-check самого discovery (`/health`);

---

## Возможности

- **Регистрация сервисов**  
  Через `POST /register` сервис сообщает о себе: `id`, `ip`, `port`, `health_path`, `description`.

- **GC “протухших” записей**  
  Фоновый поток периодически удаляет сервисы, у которых `last_seen` старше заданного TTL (например, 60 секунд).

- **Health-check самого discovery**  
  `GET /health` — простой эндпоинт для проверки, что service-discovery жив.

---

## Сборка

### На хосте для сборки:

- C++17 компилятор (g++/clang++);
- CMake;
- Библиотеки (header-only):
  - [`cpp-httplib`](https://github.com/yhirose/cpp-httplib) — HTTP сервер/клиент (`httplib.h`);
  - [`nlohmann/json`](https://github.com/nlohmann/json) — JSON (`json.hpp`).

В исходниках предполагается, что `httplib.h` и `json.hpp` лежат в `external/` или другом подключаемом каталоге и подключаются как:

### Запуск сборки

```
./build.sh
```
