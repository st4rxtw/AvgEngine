find_package(OpenGL  REQUIRED)
find_package(glfw3   REQUIRED)
find_package(glm     REQUIRED)
find_package(pugixml REQUIRED)
find_package(BASS REQUIRED)

set(DEPS_DIR   "${CMAKE_SOURCE_DIR}/deps")
set(IMGUI_DIR  "${DEPS_DIR}/ImGui")
set(IMPLOT_DIR "${DEPS_DIR}/implot")
set(GLAD_DIR "${DEPS_DIR}/glad/include")

if(NOT EXISTS "${IMGUI_DIR}/imgui.cpp")
    message(FATAL_ERROR
        "imgui not found at ${IMGUI_DIR}.\n"
        "Run setup.sh (Linux) or setup.bat (Windows) first.")
endif()
if(NOT EXISTS "${IMPLOT_DIR}/implot.cpp")
    message(FATAL_ERROR
        "implot not found at ${IMPLOT_DIR}.\n"
        "Run setup.sh (Linux) or setup.bat (Windows) first.")
endif()

foreach(_hdr imgui_impl_glfw imgui_impl_opengl3)
    if(NOT EXISTS "${IMGUI_DIR}/${_hdr}.h")
        file(CREATE_LINK "${IMGUI_DIR}/backends/${_hdr}.h"
             "${IMGUI_DIR}/${_hdr}.h" SYMBOLIC COPY_ON_ERROR)
    endif()
endforeach()
foreach(_hdr implot implot_internal)
    if(NOT EXISTS "${IMGUI_DIR}/${_hdr}.h")
        file(CREATE_LINK "${IMPLOT_DIR}/${_hdr}.h"
             "${IMGUI_DIR}/${_hdr}.h" SYMBOLIC COPY_ON_ERROR)
    endif()
endforeach()

add_library(AvgImGui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_glfw.cpp
    ${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp
    ${IMPLOT_DIR}/implot.cpp
    ${IMPLOT_DIR}/implot_items.cpp
)

target_include_directories(AvgImGui
    PUBLIC
        ${DEPS_DIR}
        ${IMGUI_DIR}
        ${IMGUI_DIR}/backends
        ${IMPLOT_DIR}
        ${GLAD_DIR}
)

target_link_libraries(AvgImGui PUBLIC glfw OpenGL::GL)

if(MSVC)
    target_compile_options(AvgImGui PRIVATE /W0)
else()
    target_compile_options(AvgImGui PRIVATE -w)
endif()

file(GLOB_RECURSE AVGENGINE_SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/Includes/*.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Includes/*.c"
)

set_source_files_properties(
    "${CMAKE_CURRENT_SOURCE_DIR}/Includes/AvgEngine/External/XML/pugixml.cpp"
    PROPERTIES HEADER_FILE_ONLY TRUE
)

add_library(AvgEngine STATIC ${AVGENGINE_SOURCES})

target_include_directories(AvgEngine
    PUBLIC
        "${CMAKE_CURRENT_SOURCE_DIR}/Includes"
)

target_compile_definitions(AvgEngine
    PUBLIC
        _CRT_SECURE_NO_WARNINGS
        UNICODE
        _UNICODE
)

if(MSVC)
    target_compile_options(AvgEngine PRIVATE
        /W3
        /MP
    )
    set_property(TARGET AvgEngine PROPERTY
        MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
else()
    target_compile_options(AvgEngine PRIVATE -Wall -Wextra)
endif()

target_link_libraries(AvgEngine
    PUBLIC
        OpenGL::GL
        glfw
        glm::glm
        AvgImGui
        pugixml::pugixml
        BASS::BASS
)
