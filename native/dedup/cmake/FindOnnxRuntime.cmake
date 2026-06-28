# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Locate a prebuilt ONNX Runtime C/C++ distribution.
#
# ONNX Runtime is intentionally NOT a vcpkg dependency: upstream ships official
# prebuilt binaries for Windows/Linux (CPU and CUDA), which are lighter to
# consume and far faster to obtain in CI than building ORT from source.
#
# Point this at a distribution one of two ways:
#   -DONNXRUNTIME_ROOT=/path/to/onnxruntime-<os>-x64-<ver>
#   or set the ONNXRUNTIME_ROOT environment variable.
# The expected layout is the upstream archive's: include/ + lib/.
#
# Defines, on success:
#   OnnxRuntime_FOUND
#   OnnxRuntime::OnnxRuntime  (imported target with includes + link lib)
#   OnnxRuntime_VERSION       (best-effort, parsed from the headers)

set(_ort_root "${ONNXRUNTIME_ROOT}")
if(NOT _ort_root)
  set(_ort_root "$ENV{ONNXRUNTIME_ROOT}")
endif()

find_path(OnnxRuntime_INCLUDE_DIR
  NAMES onnxruntime_cxx_api.h
  HINTS "${_ort_root}"
  PATH_SUFFIXES include include/onnxruntime include/onnxruntime/core/session
)

find_library(OnnxRuntime_LIBRARY
  NAMES onnxruntime
  HINTS "${_ort_root}"
  PATH_SUFFIXES lib lib64
)

# Best-effort version parse (onnxruntime ships VERSION_NUMBER in a header on
# some distributions; tolerate its absence).
set(OnnxRuntime_VERSION "unknown")
if(OnnxRuntime_INCLUDE_DIR AND EXISTS "${OnnxRuntime_INCLUDE_DIR}/onnxruntime_c_api.h")
  file(STRINGS "${OnnxRuntime_INCLUDE_DIR}/onnxruntime_c_api.h" _ort_ver_line
       REGEX "ORT_API_VERSION[ \t]+[0-9]+")
  if(_ort_ver_line)
    string(REGEX MATCH "[0-9]+" OnnxRuntime_VERSION "${_ort_ver_line}")
  endif()
endif()

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(OnnxRuntime
  REQUIRED_VARS OnnxRuntime_INCLUDE_DIR OnnxRuntime_LIBRARY
  VERSION_VAR OnnxRuntime_VERSION
)

if(OnnxRuntime_FOUND AND NOT TARGET OnnxRuntime::OnnxRuntime)
  add_library(OnnxRuntime::OnnxRuntime UNKNOWN IMPORTED)
  set_target_properties(OnnxRuntime::OnnxRuntime PROPERTIES
    IMPORTED_LOCATION "${OnnxRuntime_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${OnnxRuntime_INCLUDE_DIR}"
  )
endif()

mark_as_advanced(OnnxRuntime_INCLUDE_DIR OnnxRuntime_LIBRARY)
