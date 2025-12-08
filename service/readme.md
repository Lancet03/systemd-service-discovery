# Worker Service

Лёгкий демон на C++, который имитирует работу приложения в контейнере,  
регистрируется в **service-discovery** и периодически отправляет ему heartbeat через `systemd`-таймер.

Контейнер устроен так:

- внутри крутится **systemd**;
- при старте поднимается `worker.service`, который:
  - запускает бинарник `worker` (C++ программа, пишет что-то в лог);
  - один раз отправляет регистрацию в discovery (`register-self.sh`);
- отдельный `heartbeat.timer` каждые N секунд запускает `heartbeat.service`,
  который отправляет heartbeat в discovery (`register-self.sh`).

> Сам C++-код **ничего не знает** про discovery.  
> Вся интеграция вынесена в `systemd` + скрипты.

---

## Запуск проекта

Сборка образа

```
podman build -t worker-systemd:latest -f Containerfile .
```

Пример запуска контейнера

```powershell
podman run -d --name worker_1 --privileged --systemd=always --network host -e DISCOVERY_URL=http://127.0.0.1:8080 -e SERVICE_ID=worker_1 -e SERVICE_DESCRIPTION='Worker 1 inside systemd container' worker-systemd:latest
```
