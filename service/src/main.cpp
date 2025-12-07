#include <chrono>
#include <iostream>
#include <thread>

int main() {
    int tick = 0;
    std::cout << "[worker] started" << std::endl;

    for (;;) {
        ++tick;

        std::cout << "[worker] tick " << tick
                  << " — doing some work in container" << std::endl;

        std::this_thread::sleep_for(std::chrono::seconds(5));
    }

    return 0;
}
