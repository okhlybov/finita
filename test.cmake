
    set(test_HEADER ${CMAKE_CURRENT_SOURCE_DIR}/test_auto.h)
    set(test_SOURCES ${CMAKE_CURRENT_SOURCE_DIR}/test_auto.c)
    add_library(test-auto OBJECT ${test_SOURCES})
    target_include_directories(test-auto INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>)
  