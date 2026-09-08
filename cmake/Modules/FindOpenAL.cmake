# Find OpenAL on macOS using the system framework
find_library(OPENAL_LIBRARY
    NAMES OpenAL
    PATHS /System/Library/Frameworks
    PATH_SUFFIXES Frameworks
    DOC "OpenAL framework"
)

find_path(OPENAL_INCLUDE_DIR
    NAMES al.h
    PATHS /System/Library/Frameworks/OpenAL.framework/Headers
    DOC "OpenAL include directory"
)

if(OPENAL_LIBRARY AND OPENAL_INCLUDE_DIR)
    set(OPENAL_FOUND TRUE)
    set(OPENAL_LIBRARIES ${OPENAL_LIBRARY})
    set(OPENAL_INCLUDE_DIRS ${OPENAL_INCLUDE_DIR})
    message(STATUS "Found system OpenAL: ${OPENAL_LIBRARY}")
else()
    set(OPENAL_FOUND FALSE)
    message(WARNING "System OpenAL not found!")
endif()

mark_as_advanced(OPENAL_LIBRARY OPENAL_INCLUDE_DIR)
