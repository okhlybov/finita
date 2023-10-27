cmake_minimum_required(VERSION 3.15)

project(test)

set(AUTOC_MODULE_NAME _${PROJECT_NAME})
set(AUTOC_MODULE_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}.rb)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_LIST_DIR}/cmake)

include(AutoC)

find_package(OpenMP)

add_autoc_module(
  ${AUTOC_MODULE_NAME}
  DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
  MAIN_DEPENDENCY ${AUTOC_MODULE_SOURCE}
  COMMAND ${Ruby_EXECUTABLE} -I../../autoc/lib -I../lib ${AUTOC_MODULE_SOURCE}
)

add_executable(${PROJECT_NAME} ${PROJECT_NAME}.c)
target_compile_options(${PROJECT_NAME} PUBLIC ${OpenMP_C_FLAGS})
target_link_libraries(${PROJECT_NAME} ${AUTOC_MODULE_NAME} OpenMP::OpenMP_C)

set_property(TARGET ${PROJECT_NAME} PROPERTY C_STANDARD 11)