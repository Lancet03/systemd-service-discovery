workspace {

  model {
    user = person "Оператор" "Оператор или терминал ЧПУ, взаимодействующий с системой"

    cncSystem = softwareSystem "СЧПУ «Аксиома Контрол»" "Распределённая система ЧПУ с динамическим обнаружением сервисов" {

      discovery = container "Service Discovery" "Сервис для регистрации, мониторинга и получения списка сервисов" "Go, HTTP"
      worker1   = container "Worker 1" "Ядро ЧПУ, отправляющее heartbeat через systemd" "C++, systemd"
      worker2   = container "Worker 2" "Дополнительное ядро ЧПУ" "C++, systemd"

      user    -> discovery "Запрашивает список активных сервисов" "HTTP"
      worker1 -> discovery "Регистрация и heartbeat" "HTTP"
      worker2 -> discovery "Регистрация и heartbeat" "HTTP"
    }

    etcdSystem = softwareSystem "etcd" "Распределённое key-value хранилище, содержащее состояние сервисов"

    discovery -> etcdSystem "Запись и чтение данных о worker-сервисах" "etcd client"

    // Deployment model (обязательно в model)
    deploymentEnvironment "Production" {

      deploymentNode "Хост с Podman" "Хост сервисов" "Linux" {
        containerInstance discovery
        containerInstance worker1
        containerInstance worker2
      }

      deploymentNode "Отдельный etcd-узел" "Хост хранилища" "Linux" {
        softwareSystemInstance etcdSystem
      }
    }
  }

  views {

    systemContext cncSystem "cnc-context" {
      include *
      autoLayout lr
      description "Контекстная диаграмма: взаимодействие оператора, discovery и etcd"
    }

    container cncSystem "cnc-containers" {
      include *
      autoLayout lr
      description "Контейнерная диаграмма: компоненты системы и их взаимодействие"
    }

    deployment cncSystem "Production" "cnc-deployment" {
      include *
      autoLayout lr
      description "Deployment: Podman-хост с сервисами и отдельный узел etcd"
    }

    theme default
  }
}
