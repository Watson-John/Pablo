/*
 * SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 Pablo contributors.
 *
 * photo_core_version.h — ABI version constants.
 *
 * PHOTO_ABI_VERSION is bumped only on breaking ABI changes (struct field
 * reorder, enum value renumber, function signature change). Compatible
 * additions (new functions, new enum values appended, new fields appended
 * to POD structs) do not bump it.
 *
 * The .so/.dll/.dylib soname carries the ABI version so old + new can
 * coexist during transition: photo_core.so.1, photo_core.so.2, etc.
 *
 * Dart reads photo_abi_version() at startup and refuses to proceed if it
 * doesn't match the version the bindings were generated against.
 */

#ifndef PHOTO_CORE_VERSION_H
#define PHOTO_CORE_VERSION_H

#define PHOTO_ABI_VERSION 1

/* Build-time semantic version. Bump PATCH on every release; MINOR on
 * compatible ABI additions; MAJOR with PHOTO_ABI_VERSION on breaks.
 */
#define PHOTO_VERSION_MAJOR 0
#define PHOTO_VERSION_MINOR 1
#define PHOTO_VERSION_PATCH 0

#endif /* PHOTO_CORE_VERSION_H */
