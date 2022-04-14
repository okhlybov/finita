#
# Common CMake logic for use in CMakeWorks projects
#
# https://github.com/okhlybov/cmakeworks
#

# Set up default GCC-specific release compilation flags
if(NOT "${GNU_RELEASE_FLAGS}" STREQUAL "")
	if(${CMAKE_C_COMPILER_ID} MATCHES GNU)
		set(CMAKE_C_FLAGS_RELEASE ${GNU_RELEASE_FLAGS})
	endif()
	if(${CMAKE_CXX_COMPILER_ID} MATCHES GNU)
		set(CMAKE_CXX_FLAGS_RELEASE ${GNU_RELEASE_FLAGS})
	endif()
	if(${CMAKE_Fortran_COMPILER_ID} MATCHES GNU)
		set(CMAKE_Fortran_FLAGS_RELEASE ${GNU_RELEASE_FLAGS})
	endif()
endif()

# Set up default GCC-specific debug compilation flags
if(NOT "${GNU_DEBUG_FLAGS}" STREQUAL "")
	if(${CMAKE_C_COMPILER_ID} MATCHES GNU)
		set(CMAKE_C_FLAGS_DEBUG ${GNU_DEBUG_FLAGS})
	endif()
	if(${CMAKE_CXX_COMPILER_ID} MATCHES GNU)
		set(CMAKE_CXX_FLAGS_DEBUG ${GNU_DEBUG_FLAGS})
	endif()
	if(${CMAKE_Fortran_COMPILER_ID} MATCHES GNU)
		set(CMAKE_Fortran_FLAGS_DEBUG ${GNU_DEBUG_FLAGS})
	endif()
endif()

include(CMakeDependentOption)

# If set, PkgConfig is requested to link its modules statically
cmake_dependent_option(USE_MODULE_STATIC_LINKING "Link against PkgConfig modules statically" OFF USE_STATIC_LINKING ON)

if(NOT "${PKG_CONFIG_MODULES}" STREQUAL "")
	find_package(PkgConfig REQUIRED)
endif()

# MPI cpecific compilation configuration
if(${USE_MPI})
	find_package(MPI REQUIRED)
endif()

# Consume PkgConfig modules' command line flags
foreach(PC ${PKG_CONFIG_MODULES})
	pkg_check_modules(${PC} REQUIRED ${PC})
	target_include_directories(${PROJECT_NAME} PUBLIC ${${PC}_INCLUDE_DIRS})
	target_compile_options(${PROJECT_NAME} PUBLIC ${${PC}_CFLAGS_OTHER})
	target_link_directories(${PROJECT_NAME} PUBLIC ${${PC}_LIBRARY_DIRS})
	if(${USE_MODULE_STATIC_LINKING})
		target_link_options(${PROJECT_NAME} PUBLIC ${${PC}_STATIC_LDFLAGS_OTHER})
		target_link_libraries(${PROJECT_NAME} PUBLIC ${${PC}_STATIC_LIBRARIES})
	else()
		target_link_options(${PROJECT_NAME} PUBLIC ${${PC}_LDFLAGS_OTHER})
		target_link_libraries(${PROJECT_NAME} PUBLIC ${${PC}_LIBRARIES})
	endif()
endforeach(PC)

# GCC specific configuration
if(${CMAKE_C_COMPILER_ID} MATCHES GNU)
 	# Strip debugging information from release builds
	set(CMAKE_EXE_LINKER_FLAGS_RELEASE -s)
	# Account for static linking on demand
	if(${USE_STATIC_LINKING})
		target_link_options(${PROJECT_NAME} PUBLIC -static)
	endif()
	# Set up OpenMP flags on demand
	if(${USE_OPENMP})
		target_compile_options(${PROJECT_NAME} PUBLIC -fopenmp)
		target_link_options(${PROJECT_NAME} PUBLIC -fopenmp)
	endif()
endif()

# Assume a target always has interface headers for export which are placed alongside the sources
target_include_directories(${PROJECT_NAME} PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)

if(Fortran IN_LIST languages)
	# Specify the FORTRAN's .mod files location inside the build directory
	if(${CMAKE_GENERATOR} STREQUAL "Ninja Multi-Config")
		set(MOD_DIR ${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_BUILD_TYPE})
	else()
		set(MOD_DIR ${CMAKE_CURRENT_BINARY_DIR})
	endif()
	set_target_properties(${PROJECT_NAME} PROPERTIES Fortran_MODULE_DIRECTORY ${MOD_DIR})
	target_include_directories(${PROJECT_NAME} PUBLIC ${MOD_DIR})
endif()

# Link in MPI language-specific libraries
if(${USE_MPI})
	if(C IN_LIST languages)
		target_link_libraries(${PROJECT_NAME} PUBLIC MPI::MPI_C)
	endif()
	if(CXX IN_LIST languages)
		target_link_libraries(${PROJECT_NAME} PUBLIC MPI::MPI_CXX)
	endif()
	if(Fortran IN_LIST languages)
		target_link_libraries(${PROJECT_NAME} PUBLIC MPI::MPI_Fortran)
	endif()
endif()
