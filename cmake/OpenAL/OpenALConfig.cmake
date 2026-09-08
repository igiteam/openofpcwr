# OpenALConfig.cmake - macOS system OpenAL framework
# This file is found by find_package(OpenAL) when OpenAL_DIR is set

# Tell CMake we found OpenAL
set(OPENAL_FOUND TRUE)

# Set the library and include paths
set(OPENAL_LIBRARY "-framework OpenAL" CACHE STRING "OpenAL library" FORCE)
set(OPENAL_INCLUDE_DIR "/System/Library/Frameworks/OpenAL.framework/Headers" CACHE PATH "OpenAL include" FORCE)
set(OPENAL_LIBRARIES ${OPENAL_LIBRARY})
set(OPENAL_INCLUDE_DIRS ${OPENAL_INCLUDE_DIR})

# Create the imported target that PoseidonOpenAL expects
if(NOT TARGET OpenAL::OpenAL)
    add_library(OpenAL::OpenAL INTERFACE IMPORTED)
    set_target_properties(OpenAL::OpenAL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${OPENAL_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${OPENAL_LIBRARY}"
    )
endif()

# Also create the legacy target name some projects might expect
if(NOT TARGET OpenAL)
    add_library(OpenAL INTERFACE IMPORTED)
    set_target_properties(OpenAL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${OPENAL_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${OPENAL_LIBRARY}"
    )
endif()

message(STATUS "OpenAL: Using macOS system framework: ${OPENAL_LIBRARY}")
