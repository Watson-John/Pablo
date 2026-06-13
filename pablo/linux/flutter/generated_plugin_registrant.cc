//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <photo_native/photo_native_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) photo_native_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "PhotoNativePlugin");
  photo_native_plugin_register_with_registrar(photo_native_registrar);
}
