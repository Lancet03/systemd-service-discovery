cmake_minimum_required(VERSION 3.10)
project(discovery_cpp)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(discovery
    main.cpp
)

target_include_directories(discovery PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/external
)