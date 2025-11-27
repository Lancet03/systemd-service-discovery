#include <chrono>
#include <iostream>
#include <map>
#include <mutex>
#include <string>
#include <thread>

// external
#include "httplib.h"
#include "json.hpp"


using json = nlohmann::json;
using namespace std::chrono;

struct Service {
    std::string id;
    std::string ip;
    std::string description;
    system_clock::time_point last_seen;
};

std::map<std::string, Service> registry;
std::mutex registry_mutex;

// сколько времени запись считается живой без heartbeat
constexpr auto TTL = 60s;

std::string to_iso8601(const system_clock::time_point &tp) {
    std::time_t t = system_clock::to_time_t(tp);
    std::tm tm{};
    gmtime_r(&t, &tm);

    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

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

int main() {
    httplib::Server svr;

    // POST /register
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
                // если IP не передан — берём из соединения
                svc.ip = req.remote_addr;
            }

            if (body.contains("description") && body["description"].is_string()) {
                svc.description = body["description"].get<std::string>();
            }

            svc.last_seen = system_clock::now();

            {
                std::lock_guard<std::mutex> lock(registry_mutex);
                registry[svc.id] = svc;
            }

            std::cout << "[REG] id=" << svc.id
                      << " ip=" << svc.ip
                      << " desc=\"" << svc.description << "\"\n";

            res.status = 204; // No Content
        } catch (const std::exception &e) {
            res.status = 400;
            res.set_content(std::string("bad json: ") + e.what(), "text/plain");
        }
    });

    // GET /services
    svr.Get("/services", [](const httplib::Request &req, httplib::Response &res) {
        json arr = json::array();
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            for (const auto &[id, svc] : registry) {
                arr.push_back({
                    {"id",          svc.id},
                    {"ip",          svc.ip},
                    {"description", svc.description},
                    {"last_seen",   to_iso8601(svc.last_seen)}
                });
            }
        }

        res.set_content(arr.dump(2), "application/json");
    });

    std::thread gc_thread(gc_loop);
    gc_thread.detach();

    std::cout << "Discovery service listening on 0.0.0.0:8080\n";
    if (!svr.listen("0.0.0.0", 8080)) {
        std::cerr << "Failed to bind to port 8080\n";
        return 1;
    }

    return 0;
}
