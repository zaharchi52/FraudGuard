cmake_minimum_required(VERSION 3.16)
project(FraudGuardCpp VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
    add_compile_options(/EHsc)
endif()

add_library(fraudguard_core src/engine.cpp src/csv_io.cpp)
target_include_directories(fraudguard_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
if(MSVC)
    target_compile_options(fraudguard_core PRIVATE /W4)
else()
    target_compile_options(fraudguard_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

add_executable(fraudguard src/main.cpp)
target_link_libraries(fraudguard PRIVATE fraudguard_core)

include(CTest)

option(FRAUDGUARD_USE_GTEST "Build Google Test unit tests when available" ON)
option(FRAUDGUARD_FETCH_GTEST "Download Google Test when it is not installed" OFF)

if(BUILD_TESTING)
    # Dependency-free integration checks always run, including Release builds.
    add_executable(fraudguard_smoke_tests tests/smoke_tests.cpp)
    target_link_libraries(fraudguard_smoke_tests PRIVATE fraudguard_core)
    add_test(NAME fraudguard_smoke_tests COMMAND fraudguard_smoke_tests)
    set_tests_properties(fraudguard_smoke_tests PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    )

    if(FRAUDGUARD_USE_GTEST)
        find_package(GTest QUIET)

        if(NOT TARGET GTest::gtest_main AND FRAUDGUARD_FETCH_GTEST)
            include(FetchContent)
            set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
            FetchContent_Declare(
                googletest
                GIT_REPOSITORY https://github.com/google/googletest.git
                GIT_TAG v1.15.2
            )
            FetchContent_MakeAvailable(googletest)
        endif()

        if(TARGET GTest::gtest_main)
            add_executable(fraudguard_tests tests/engine_tests.cpp)
            target_link_libraries(fraudguard_tests PRIVATE fraudguard_core GTest::gtest_main)
            include(GoogleTest)
            gtest_discover_tests(fraudguard_tests)
            message(STATUS "Google Test found: extended unit tests are enabled")
        else()
            message(STATUS "Google Test not found: only dependency-free smoke tests are enabled. Use -DFRAUDGUARD_FETCH_GTEST=ON to download it.")
        endif()
    endif()
endif()
