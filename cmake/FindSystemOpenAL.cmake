# Use macOS system OpenAL
find_library(OPENAL_LIBRARY OpenAL)
find_path(OPENAL_INCLUDE_DIR OpenAL/al.h)

if(OPENAL_LIBRARY)
    set(OPENAL_FOUND TRUE)
    set(OPENAL_LIBRARIES ${OPENAL_LIBRARY})
    set(OPENAL_INCLUDE_DIRS ${OPENAL_INCLUDE_DIR})
    message(STATUS "Using system OpenAL: ${OPENAL_LIBRARY}")
endif()
