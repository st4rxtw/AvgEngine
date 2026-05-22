add_executable(Demo Demo.cpp)

target_link_libraries(Demo PRIVATE AvgEngine)

if(WIN32)
    find_file(BASS_DLL    NAMES bass.dll    HINTS "${BASS_DIR}" "${BASS_DIR}/x64")
    find_file(BASS_FX_DLL NAMES bass_fx.dll HINTS "${BASS_DIR}" "${BASS_DIR}/x64")

    if(BASS_DLL)
        add_custom_command(TARGET Demo POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${BASS_DLL}" "$<TARGET_FILE_DIR:Demo>"
            COMMENT "Copying bass.dll")
    endif()

    if(BASS_FX_DLL)
        add_custom_command(TARGET Demo POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${BASS_FX_DLL}" "$<TARGET_FILE_DIR:Demo>"
            COMMENT "Copying bass_fx.dll")
    endif()
endif()
