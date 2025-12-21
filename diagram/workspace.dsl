workspace {

  model {
    user = person "Оператор" "Оператор или терминал ЧПУ, взаимодействующий с системой"

    cncSystem = softwareSystem "СЧПУ «Аксиома Контрол»" "Распределённая система ЧПУ с динамическим обнаружением сервисов" {
      worker = container "Worker (N экземпляров)" "Ядро/воркер ЧПУ. Экземпляров может быть много; каждый периодически регистрируется и отправляет heartbeat через systemd." "C++, systemd"
    }

    serviceDiscovery = softwareSystem "Service Discovery" "Централизованный сервис обнаружения: регистрация/heartbeat и выдача списка доступных сервисов" {
      discoveryApi = container "Discovery API" "Принимает регистрацию/heartbeat и отдает resolve (список активных инстансов)." "Go, HTTP"
      registryStore = container "Registry Store (etcd)" "Распределённое key-value хранилище состояния реестра (instances, TTL/lease, metadata)." "etcd" {
        tags "Database"
      }
    }

    // Relationships
    user -> discoveryApi "Запрашивает список активных сервисов" "HTTP"
    worker -> discoveryApi "Регистрация и heartbeat" "HTTP"
    discoveryApi -> registryStore "Запись и чтение данных о worker-инстансах (TTL/lease)" "etcd client"

    // Deployment model
    deploymentEnvironment "Production" {

      deploymentNode "Хост с Podman" "Хост сервисов" "Linux" {
        containerInstance worker
        containerInstance discoveryApi
      }

      deploymentNode "Отдельный etcd-узел" "Хост хранилища" "Linux" {
        containerInstance registryStore
      }
    }
  }

  views {

    systemContext cncSystem "cnc-context" {
      include *
      autoLayout lr
      description "Контекстная диаграмма: взаимодействие оператора, воркеров (N) и Service Discovery"
    }

    container cncSystem "cnc-containers" {
      include *
      autoLayout lr
      description "Контейнерная диаграмма CNC-системы: Worker (N экземпляров) и взаимодействие с Service Discovery"
    }

    container serviceDiscovery "discovery-containers" {
      include *
      autoLayout tb
      description "Контейнерная диаграмма Service Discovery: API (Go) и внутреннее хранилище реестра (etcd)"
    }

    deployment cncSystem "Production" "cnc-deployment" {
      include *
      autoLayout lr
      description "Deployment: Podman-хост с worker-ами и Discovery API, отдельный узел etcd"
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

    theme default
  }
}
