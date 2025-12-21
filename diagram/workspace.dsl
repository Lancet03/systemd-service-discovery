workspace "Service Discovery (Go + etcd + systemd)" "Diploma-level C4 model with tech choices and flows" {

  model {
    operator = person "Operator" "Администрирует инфраструктуру и наблюдает состояние сервисов."
    developer = person "Developer" "Разворачивает сервисы и настраивает регистрацию."

    ecosystem = softwareSystem "Service Ecosystem" "Клиенты и сервисы, использующие service discovery." {
      clientApp = container "Client Application" "Запрашивает список доступных сервисов и параметры подключения." "Any"
      serviceX = container "serviceX" "Пример сервиса, который должен быть обнаружен через discovery." "Any"
      regAgentX = container "Registration Job (systemd)" "systemd oneshot unit выполняет POST /register (это же heartbeat); systemd timer запускает oneshot по расписанию." "systemd + curl/bash"
    }

    discovery = softwareSystem "Service Discovery" "Централизованный реестр: регистрация/обновление живости и выдача endpoints." {
      discoveryApi = container "Discovery API" "HTTP API: принимает /register и отдаёт /resolve; обновляет TTL/lease при каждом /register." "Go"
      etcdStore = container "Registry Store" "Хранилище записей сервисов и TTL/lease (ключи по префиксам)." "etcd" {
        tags "Database"
      }
    }

    developer -> ecosystem "Развёртывание и настройка systemd unit/timer"
    operator -> discovery "Эксплуатация и контроль"

    regAgentX -> discoveryApi "POST /register (register + heartbeat)" "HTTP/HTTPS"
    clientApp -> discoveryApi "GET /resolve?name=serviceX (получить endpoints)" "HTTP/HTTPS"

    discoveryApi -> clientApp "Список instances: ip:port + metadata (JSON)" "JSON"
    discoveryApi -> etcdStore "Put/Get keys: /services/<name>/<instanceId> + TTL/lease" "etcd client"
  }

  views {
    systemContext discovery "discovery-context" "System Context: взаимодействие с Service Discovery" {
      include *
      autolayout lr
    }

    container discovery "discovery-containers" "Containers: Go API + etcd" {
      include *
      autolayout lr
    }

    container ecosystem "ecosystem-containers" "Ecosystem: client + service + systemd registration job" {
      include *
      autolayout lr
    }

    dynamic discovery "register-heartbeat-flow" "Dynamic: /register as heartbeat (systemd oneshot + timer)" {
      title "Registration/Heartbeat flow"
      regAgentX -> discoveryApi "POST /register {name, instanceId, ip, port, ttl, meta}"
      discoveryApi -> etcdStore "PUT /services/serviceX/<instanceId> (refresh TTL/lease)"
      autolayout lr
    }

    dynamic discovery "resolve-flow" "Dynamic: client resolves endpoints" {
      title "Resolve flow"
      clientApp -> discoveryApi "GET /resolve?name=serviceX"
      discoveryApi -> etcdStore "GET prefix /services/serviceX/* (only active by TTL/lease)"
      discoveryApi -> clientApp "200 OK: [{ip,port,meta}...]"
      autolayout lr
    }

styles {
  element "Person" {
    shape Person
  }

  element "Software System" {
    background "#0b4f8a"
    color "#ffffff"
  }

  element "Container" {
    background "#1e78c8"
    color "#ffffff"
  }

  element "Database" {
    shape Cylinder
  }
}

  }
}
