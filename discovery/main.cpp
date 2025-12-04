#include <chrono>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "httplib.h"    // cpp-httplib (server + client)
#include "json.hpp"     // nlohmann/json

using json = nlohmann::json;
using namespace std::chrono;

struct Service {
    std::string id;
    std::string ip;
    std::string description;
    int         port            = 80;        // порт сервиса (по умолчанию 80)
    std::string health_path     = "/health"; // путь health-чека

    bool        alive           = false;     // доступен ли сервис по сети
    bool        ready           = false;     // готов ли обслуживать запросы

    system_clock::time_point last_seen{};
    system_clock::time_point last_health_check{};
};

std::map<std::string, Service> registry;
std::mutex registry_mutex;

// сколько времени запись живёт без heartbeat / health-check
constexpr auto TTL = 60s;
// период активных health-check'ов
constexpr auto HEALTH_INTERVAL = 10s;

std::string to_iso8601(const system_clock::time_point &tp) {
    std::time_t t = system_clock::to_time_t(tp);
    std::tm tm{};
    gmtime_r(&t, &tm);

    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

// Фоновая очистка "протухших" сервисов
void gc_loop() {
    while (true) {
        std::this_thread::sleep_for(10s);
        auto cutoff = system_clock::now() - TTL;

        std::lock_guard<std::mutex> lock(registry_mutex);
        for (auto it = registry.begin(); it != registry.end(); ) {
            if (it->second.last_seen < cutoff) {
                std::cout << "[GC] removing stale service: " << it->first << "\n";
                it = registry.erase(it);
            } else {
                ++it;
            }
        }
    }
}

// Фоновый активный health-check
void health_check_loop() {
    while (true) {
        std::this_thread::sleep_for(HEALTH_INTERVAL);

        // Делаем снапшот списка сервисов, чтобы не держать мьютекс во время сетевых вызовов
        std::vector<Service> snapshot;
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            snapshot.reserve(registry.size());
            for (const auto &kv : registry) {
                snapshot.push_back(kv.second);
            }
        }

        for (const auto &svc_snapshot : snapshot) {
            try {
                httplib::Client cli(svc_snapshot.ip, svc_snapshot.port);
                cli.set_read_timeout(5, 0);   // 5 секунд
                cli.set_connection_timeout(5, 0);

                auto res = cli.Get(svc_snapshot.health_path.c_str());
                bool alive = false;
                bool ready = false;

                if (res && res->status == 200) {
                    alive = true;

                    // Пытаемся прочитать ready из JSON: { "ready": true }
                    try {
                        auto j = json::parse(res->body);
                        if (j.contains("ready") && j["ready"].is_boolean()) {
                            ready = j["ready"].get<bool>();
                        } else {
                            // Если поля нет, считаем, что раз /health 200 — сервис готов
                            ready = true;
                        }
                    } catch (...) {
                        // Ответ не JSON — считаем ready = true, раз код 200
                        ready = true;
                    }
                } else {
                    alive = false;
                    ready = false;
                }

                {
                    std::lock_guard<std::mutex> lock(registry_mutex);
                    auto it = registry.find(svc_snapshot.id);
                    if (it != registry.end()) {
                        it->second.alive             = alive;
                        it->second.ready             = ready;
                        it->second.last_health_check = system_clock::now();

                        // Если health-check успешен, обновим last_seen, чтобы не удалить по TTL
                        if (alive) {
                            it->second.last_seen = system_clock::now();
                        }
                    }
                }

                std::cout << "[HC] " << svc_snapshot.id
                          << " alive=" << (alive ? "true" : "false")
                          << " ready=" << (ready ? "true" : "false") << "\n";

            } catch (const std::exception &e) {
                std::lock_guard<std::mutex> lock(registry_mutex);
                auto it = registry.find(svc_snapshot.id);
                if (it != registry.end()) {
                    it->second.alive             = false;
                    it->second.ready             = false;
                    it->second.last_health_check = system_clock::now();
                }
                std::cerr << "[HC] exception for " << svc_snapshot.id << ": " << e.what() << "\n";
            }
        }
    }
}

int main() {
    httplib::Server svr;

    // Регистрация / heartbeat
    svr.Post("/register", [](const httplib::Request &req, httplib::Response &res) {
        try {
            auto body = json::parse(req.body);

            if (!body.contains("id") || !body["id"].is_string()) {
                res.status = 400;
                res.set_content("field 'id' is required", "text/plain");
                return;
            }

            Service svc;
            svc.id = body["id"].get<std::string>();

            if (body.contains("ip") && body["ip"].is_string()) {
                svc.ip = body["ip"].get<std::string>();
            } else {
                svc.ip = req.remote_addr;
            }

            if (body.contains("description") && body["description"].is_string()) {
                svc.description = body["description"].get<std::string>();
            }

            if (body.contains("port") && body["port"].is_number_integer()) {
                svc.port = body["port"].get<int>();
            } else {
                svc.port = 80;
            }

            if (body.contains("health_path") && body["health_path"].is_string()) {
                svc.health_path = body["health_path"].get<std::string>();
            } else {
                svc.health_path = "/health";
            }

            svc.last_seen = system_clock::now();
            svc.last_health_check = system_clock::time_point{};
            svc.alive = false; // до первого health-check
            svc.ready = false;

            {
                std::lock_guard<std::mutex> lock(registry_mutex);
                registry[svc.id] = svc;
            }

            std::cout << "[REG] id=" << svc.id
                      << " ip=" << svc.ip << ":" << svc.port
                      << " desc=\"" << svc.description << "\""
                      << " health_path=" << svc.health_path << "\n";

            res.status = 204; // No Content
        } catch (const std::exception &e) {
            res.status = 400;
            res.set_content(std::string("bad json: ") + e.what(), "text/plain");
        }
    });

    // Получение списка сервисов
    svr.Get("/services", [](const httplib::Request &req, httplib::Response &res) {
        json arr = json::array();
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            for (const auto &[id, svc] : registry) {
                arr.push_back({
                    {"id",               svc.id},
                    {"ip",               svc.ip},
                    {"port",             svc.port},
                    {"description",      svc.description},
                    {"health_path",      svc.health_path},
                    {"alive",            svc.alive},
                    {"ready",            svc.ready},
                    {"last_seen",        to_iso8601(svc.last_seen)},
                    {"last_health_check", svc.last_health_check.time_since_epoch().count() == 0
                                             ? nullptr
                                             : json(to_iso8601(svc.last_health_check))}
                });
            }
        }

        res.set_content(arr.dump(2), "application/json");
    });

    // Можно добавить простой /health самого discovery
    svr.Get("/health", [](const httplib::Request &, httplib::Response &res) {
        res.status = 200;
        res.set_content(R"({"ready": true})", "application/json");
    });

    std::thread gc_thread(gc_loop);
    gc_thread.detach();

    std::thread hc_thread(health_check_loop);
    hc_thread.detach();

    std::cout << "Discovery service listening on 0.0.0.0:8080\n";
    if (!svr.listen("0.0.0.0", 8080)) {
        std::cerr << "Failed to bind to port 8080\n";
        return 1;
    }

    return 0;
}
