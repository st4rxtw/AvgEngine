find_path(BASS_INCLUDE_DIR
    NAMES Bass/bass.h bass.h
    HINTS
        "${BASS_DIR}"
        "${BASS_DIR}/include"
        "${CMAKE_CURRENT_SOURCE_DIR}/AvgEngine/Includes"
)

if(WIN32)
    set(_bass_arch_hint "${BASS_DIR}/x64")
    if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        set(_bass_arch_hint "${BASS_DIR}")
    endif()
    find_library(BASS_LIBRARY
        NAMES bass
        HINTS "${_bass_arch_hint}" "${BASS_DIR}" "${BASS_DIR}/lib"
    )
    find_library(BASS_FX_LIBRARY
        NAMES bass_fx
        HINTS "${_bass_arch_hint}" "${BASS_DIR}" "${BASS_DIR}/lib"
    )
else()
    find_library(BASS_LIBRARY
        NAMES bass
        HINTS "${BASS_DIR}" "${BASS_DIR}/lib"
    )
    find_library(BASS_FX_LIBRARY
        NAMES bass_fx
        HINTS "${BASS_DIR}" "${BASS_DIR}/lib"
    )
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(BASS
    REQUIRED_VARS BASS_LIBRARY BASS_INCLUDE_DIR
    FAIL_MESSAGE
        "BASS not found. Download from https://www.un4seen.com and set -DBASS_DIR=<SDK root>."
)

if(BASS_FOUND AND NOT TARGET BASS::BASS)
    add_library(BASS::BASS UNKNOWN IMPORTED)
    set_target_properties(BASS::BASS PROPERTIES
        IMPORTED_LOCATION             "${BASS_LIBRARY}"
        INTERFACE_INCLUDE_DIRECTORIES "${BASS_INCLUDE_DIR}"
    )

    if(BASS_FX_LIBRARY)
        add_library(BASS::FX UNKNOWN IMPORTED)
        set_target_properties(BASS::FX PROPERTIES
            IMPORTED_LOCATION "${BASS_FX_LIBRARY}"
        )
        set_property(TARGET BASS::BASS APPEND PROPERTY
            INTERFACE_LINK_LIBRARIES BASS::FX)
    endif()
endif()

mark_as_advanced(BASS_INCLUDE_DIR BASS_LIBRARY BASS_FX_LIBRARY)