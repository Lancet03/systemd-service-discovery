workspace {

  model {
    user = person "Оператор" "Оператор или терминал ЧПУ, взаимодействующий с системой"

    cncSystem = softwareSystem "СЧПУ «Аксиома Контрол»" "Ядра СЧПУ с systemd-оболочкой. N экземпляров периодически регистрируются и отправляют heartbeat через systemd." {
      systemd = container "Systemd" "Обертка над ядром, посылающая запросы /heartbeat" "systemd"
      core = container "Ядро CЧПУ «Аксиома Контрол»" "" "C++"
    }

    serviceDiscovery = softwareSystem "Service Discovery" "Централизованный сервис обнаружения: регистрация/heartbeat и выдача списка доступных сервисов" {
      discoveryApi = container "Discovery API" "Принимает регистрацию/heartbeat и отдает resolve (список активных инстансов)." "Go, HTTP"
      registryStore = container "Registry Store (etcd)" "Распределённое key-value хранилище состояния реестра (instances, TTL/lease, metadata)." "etcd" {
        tags "Database"
      }
    }

    // Relationships
    user -> discoveryApi "Запрашивает список активных сервисов" "HTTP"
    systemd -> discoveryApi "Регистрация и heartbeat" "HTTP"
    systemd -> core "Запуск ядра"
    discoveryApi -> registryStore "Запись и чтение данных о systemd-инстансах (TTL/lease)" "etcd client"

    // Deployment model
    deploymentEnvironment "Production" {

      deploymentNode "Хост с Podman" "Хост сервисов" "Linux" {
        containerInstance systemd
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
      description "Контейнерная диаграмма CNC-системы: СЧПУ (N экземпляров) и взаимодействие с Service Discovery"
    }

    container serviceDiscovery "discovery-containers" {
      include *
      autoLayout tb
      description "Контейнерная диаграмма Service Discovery: API (Go) и внутреннее хранилище реестра (etcd)"
    }

    deployment cncSystem "Production" "cnc-deployment" {
      include *
      autoLayout lr
      description "Deployment: Podman-хост с СЧПУ (N-экземпляров) и Discovery API, отдельный узел etcd"
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
