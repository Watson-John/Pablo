# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Pablo contributors.
#
# Pablo native backend plugin for Flutter macOS.
#
# CocoaPods symlinks the plugin under `<app>/macos/Flutter/ephemeral/.symlinks/`,
# which breaks (a) logical `..` resolution in HEADER_SEARCH_PATHS and
# (b) source_files globbing through directory symlinks. We work around both
# by maintaining two checked-in symlinks in this directory:
#
#   - `Classes/core/*.cpp`  — individual file symlinks to native/core/src/**.cpp.
#                             Individual file symlinks survive the .symlinks
#                             hop where directory globs do not.
#   - `_native_core/`       — directory symlink to native/core/, used solely
#                             for HEADER_SEARCH_PATHS resolution.
#
# Both are created (and refreshed when new sources are added) by:
#   tools/setup-plugin-symlinks.sh
#
# We can move to a pre-built .xcframework approach later if cold-build time
# becomes an issue or if we want to avoid the symlinks-in-repo footprint.

Pod::Spec.new do |s|
  s.name             = 'photo_native'
  s.version          = '0.1.0'
  s.summary          = 'Pablo native backend (FFI + texture registrar) — macOS.'
  s.description      = 'Native C++ image pipeline and texture bridge for the Pablo Flutter app.'
  s.homepage         = 'https://example.invalid/pablo'
  s.license          = { :type => 'Apache-2.0', :file => '../../../LICENSES.md' }
  s.author           = { 'Pablo contributors' => 'noreply@example.invalid' }
  s.platform         = :osx, '13.0'
  s.swift_version    = '5.0'

  s.source           = { :path => '.' }

  s.source_files = ['Classes/**/*.{h,mm,cpp}']
  s.public_header_files = 'Classes/PhotoNativePlugin.h'
  s.preserve_paths      = ['_native_core/**/*.{h,cpp}']

  s.dependency 'FlutterMacOS'

  # ---- libvips (Homebrew) for the M3 real-decode path ----
  # Resolved at pod-install time. If libvips isn't installed (or pkg-config
  # can't describe it), the plugin still builds and falls back to the M2
  # synthetic path — PHOTO_HAVE_VIPS simply stays undefined.
  vips_defs   = ''
  vips_cflags = ''
  vips_libs   = ''
  vips_prefix = `brew --prefix vips 2>/dev/null`.strip
  unless vips_prefix.empty?
    brew_root = `brew --prefix 2>/dev/null`.strip
    glib_pfx  = `brew --prefix glib 2>/dev/null`.strip
    pkg_dirs  = [vips_prefix, glib_pfx, brew_root].reject(&:empty?)
                  .map { |p| "#{p}/lib/pkgconfig" }.join(':')
    cflags = `PKG_CONFIG_PATH=#{pkg_dirs} pkg-config --cflags vips 2>/dev/null`.strip
    libs   = `PKG_CONFIG_PATH=#{pkg_dirs} pkg-config --libs vips 2>/dev/null`.strip
    unless cflags.empty? || libs.empty?
      vips_defs   = ' PHOTO_HAVE_VIPS=1'
      vips_cflags = cflags
      vips_libs   = " #{libs}"
    end
  end

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'              => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++20',
    'CLANG_CXX_LIBRARY'           => 'libc++',
    'GCC_C_LANGUAGE_STANDARD'     => 'c11',
    'HEADER_SEARCH_PATHS' => [
      '"$(PODS_TARGET_SRCROOT)/Classes"',
      '"$(PODS_TARGET_SRCROOT)/_native_core/include"',
      '"$(PODS_TARGET_SRCROOT)/_native_core/src"',
    ].join(' '),
    'OTHER_CPLUSPLUSFLAGS' => "$(inherited) #{vips_cflags}",
    'GCC_PREPROCESSOR_DEFINITIONS' => "PHOTO_BUILD_STATIC=1#{vips_defs}",
    # Default visibility — hiding it breaks Obj-C class symbol export, which
    # GeneratedPluginRegistrant references. C++ internal symbols inside
    # photo_core stay hidden via the namespace anyway; PHOTO_API marks the
    # C ABI exports explicitly.
    # FlutterMacOS framework lives in the Flutter tool's per-build output dir
    # ($BUILT_PRODUCTS_DIR by the time the plugin links). The framework
    # search path is inherited from the parent project but we add it
    # explicitly so the plugin framework links cleanly under use_frameworks!.
    'FRAMEWORK_SEARCH_PATHS' => '$(inherited) "${PODS_CONFIGURATION_BUILD_DIR}/FlutterMacOS"',
    'OTHER_LDFLAGS' => "$(inherited) -framework FlutterMacOS#{vips_libs}",
  }
end
