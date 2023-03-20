cmake_minimum_required(VERSION 3.15)

find_package(Ruby 3.2)

if(NOT Ruby_FOUND)
  message(STATUS "Attempting to locate default Ruby executable")
  find_program(Ruby_EXECUTABLE ruby REQUIRED)
endif()

find_program(Astyle_EXECUTABLE astyle REQUIRED)

function(add_autoc_module module)
  set(args DIRECTORY MAIN_DEPENDENCY)
  set(listArgs COMMAND DEPENDS)
  cmake_parse_arguments(key "${flags}" "${args}" "${listArgs}" ${ARGN})
  if(NOT key_DIRECTORY)
    set(key_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
  endif()
  if(NOT key_MAIN_DEPENDENCY)
    set(key_MAIN_DEPENDENCY ${key_DIRECTORY}/${module}.rb)
  endif()
  set(module_state ${key_DIRECTORY}/${module}.state)
  set(module_cmake ${key_DIRECTORY}/${module}.cmake)
  set(module_target ${module}-generate)
  if(NOT EXISTS ${module_state} OR NOT EXISTS ${module_cmake})
    message(CHECK_START "Bootstrapping AutoC module " ${module})
    execute_process(WORKING_DIRECTORY ${key_DIRECTORY} COMMAND ${key_COMMAND} VERBATIM)
  endif()
  include(${module_cmake})
  add_custom_command(
    OUTPUT ${module_state}
    BYPRODUCTS ${module_cmake} fake
    MAIN_DEPENDENCY ${key_MAIN_DEPENDENCY}
    DEPENDS ${key_DEPENDS}
    WORKING_DIRECTORY ${key_DIRECTORY}
    COMMAND ${key_COMMAND}
    COMMAND ${Astyle_EXECUTABLE} -n ${${module}_HEADER} ${${module}_SOURCES}
    VERBATIM
  )
  add_custom_target(${module_target} DEPENDS ${module_state})
  add_dependencies(${module} ${module_target})
endfunction()
