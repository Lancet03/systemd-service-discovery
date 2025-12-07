cmake_minimum_required(VERSION 3.10)
project(service_app)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(worker main.cpp)

if(UNIX)
    target_link_libraries(worker PRIVATE pthread)
endif()
