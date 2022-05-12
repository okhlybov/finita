#
# Sample multiplatform CMake project to build multilanguage (C/C++/FORTRAN) program
# with optional MPI, OpenMP and PkgConfig support
#
# https://github.com/okhlybov/cmakeworks/program
#

# **** Asterisks indicate the level of importance for customization

# *
# Set up CMake compatibility level
cmake_minimum_required(VERSION 3.16) # Ninja Multi-Config requires 3.17+

### Basic project setup

# ****
# Set to project name from which the executable name will be deduced
# Specify languages the program is written in
project(c0 LANGUAGES C)

find_program(Ruby_EXECUTABLE ruby)

find_program(AStyle NAMES astyle REQUIRED)

# Source code formatting with AStyle is mandatory for proper Doxygen operation
add_custom_command(
    OUTPUT fake ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}_auto.c ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}_auto.h
    DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}.rb
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMAND ${Ruby_EXECUTABLE} -I. -I../lib -I../ext/autoc/lib ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}.rb
    COMMAND ${AStyle} -n ${PROJECT_NAME}_auto.c ${PROJECT_NAME}_auto.h
    VERBATIM
)

# Use fake dependency to force code rebuild on every CMake invokation
add_custom_target(auto DEPENDS fake)

# ****
# Instruct to create a named executable from the space-separated list of source files which consitute the program
add_executable(${PROJECT_NAME} ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}_auto.c ${CMAKE_CURRENT_SOURCE_DIR}/${PROJECT_NAME}.c)

# ***
# Set to the space-separated list of dependent PkgConfig modules
set(PKG_CONFIG_MODULES)

# **
# If set, accounts for static linking (forces setting the USE_MODULE_STATIC_LINKING option)
set(USE_STATIC_LINKING OFF)

# ****
# If set, instruct the build system to compile sources with MPI-aware compiler drivers
# and to link against the appropriate libraries
set(USE_MPI OFF)

# ****
# If set, instruct the build system to emit OpenMP support flags
set(USE_OPENMP OFF)

### Advanced project configuration

# ***
# Enforce language-specific standards
target_compile_features(${PROJECT_NAME} PRIVATE c_std_99)

# *
# Specify space-separated list of additional include directories specified as -I command line arguments
# Current directory is considered to contain a public interface and hence is already included by the CMakeWorks common code
# target_include_directories(${PROJECT_NAME} PRIVATE .)

# **
# Specify space-separated list of preprocessor macro definitions specified as -D command line arguments
target_compile_definitions(${PROJECT_NAME} PRIVATE)

# *
# Specify GCC-specific optimization flags
# Set it to empty string or comment it out to revert to default configuration behavior
set(GNU_RELEASE_FLAGS "-pipe -Ofast -march=native -ffast-math -Wall -pedantic -g -DNDEBUG -pg")
set(CLANG_RELEASE_FLAGS ${GNU_RELEASE_FLAGS})

# *
# Specify GCC-specific debugging flags
# Set it to empty string or comment it out to revert to default configuration behavior
set(GNU_DEBUG_FLAGS "-pipe -g -Og -Wall -pedantic")

# Slurp in the common logics code
list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/../cmake)
include(CMakeWorks)