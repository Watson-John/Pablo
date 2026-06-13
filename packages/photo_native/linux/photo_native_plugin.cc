// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 Pablo contributors.

#include "include/photo_native/photo_native_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <gmodule.h>

#include <stdint.h>

#include "photo_core.h"
#include "photo_native_texture.h"

#define PHOTO_NATIVE_PLUGIN(obj) \
    (G_TYPE_CHECK_INSTANCE_CAST((obj), photo_native_plugin_get_type(), \
                                PhotoNativePlugin))

struct _PhotoNativePlugin {
    GObject              parent_instance;
    FlPluginRegistrar   *registrar;
    FlMethodChannel     *channel;
    GHashTable          *textures_by_slot;  // uint64 -> PhotoNativeTexture*
    photo_engine_t      *engine;
};

G_DEFINE_TYPE(PhotoNativePlugin, photo_native_plugin, G_TYPE_OBJECT)

static FlMethodResponse *call_attach_engine(PhotoNativePlugin *self,
                                            FlValue *args) {
    FlValue *handle = fl_value_lookup_string(args, "engineHandle");
    if (handle == nullptr || fl_value_get_type(handle) != FL_VALUE_TYPE_INT) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "BAD_ARGS", "missing engineHandle", nullptr));
    }
    int64_t h = fl_value_get_int(handle);
    self->engine = reinterpret_cast<photo_engine_t *>((uintptr_t)h);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static FlMethodResponse *call_register(PhotoNativePlugin *self,
                                       FlValue *args) {
    if (self->engine == nullptr) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "NOT_ATTACHED", "attachEngine must be called first", nullptr));
    }
    FlValue *slot = fl_value_lookup_string(args, "slotId");
    if (slot == nullptr || fl_value_get_type(slot) != FL_VALUE_TYPE_INT) {
        return FL_METHOD_RESPONSE(fl_method_error_response_new(
            "BAD_ARGS", "missing slotId", nullptr));
    }
    uint64_t sid = (uint64_t)fl_value_get_int(slot);

    PhotoNativeTexture *tex = photo_native_texture_new(sid, self->engine);
    int64_t texture_id = fl_texture_registrar_register_texture(
        fl_plugin_registrar_get_texture_registrar(self->registrar),
        FL_TEXTURE(tex));

    g_hash_table_insert(self->textures_by_slot,
                        g_memdup2(&sid, sizeof(sid)),
                        tex);  // takes ownership of ref

    g_autoptr(FlValue) ret = fl_value_new_int(texture_id);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(ret));
}

static FlMethodResponse *call_unregister(PhotoNativePlugin *self,
                                         FlValue *args) {
    FlValue *slot = fl_value_lookup_string(args, "slotId");
    if (slot == nullptr || fl_value_get_type(slot) != FL_VALUE_TYPE_INT) {
        return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    }
    uint64_t sid = (uint64_t)fl_value_get_int(slot);
    g_hash_table_remove(self->textures_by_slot, &sid);
    return FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
}

static void method_call_cb(FlMethodChannel *channel, FlMethodCall *call,
                           gpointer user_data) {
    auto *self = PHOTO_NATIVE_PLUGIN(user_data);
    const gchar *method = fl_method_call_get_name(call);
    FlValue *args = fl_method_call_get_args(call);

    g_autoptr(FlMethodResponse) response = nullptr;
    if (g_strcmp0(method, "attachEngine") == 0) {
        response = call_attach_engine(self, args);
    } else if (g_strcmp0(method, "register") == 0) {
        response = call_register(self, args);
    } else if (g_strcmp0(method, "unregister") == 0) {
        response = call_unregister(self, args);
    } else {
        response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    g_autoptr(GError) error = nullptr;
    fl_method_call_respond(call, response, &error);
}

static void photo_native_plugin_dispose(GObject *object) {
    auto *self = PHOTO_NATIVE_PLUGIN(object);
    g_clear_pointer(&self->textures_by_slot, g_hash_table_destroy);
    g_clear_object(&self->channel);
    g_clear_object(&self->registrar);
    G_OBJECT_CLASS(photo_native_plugin_parent_class)->dispose(object);
}

static void photo_native_plugin_class_init(PhotoNativePluginClass *klass) {
    G_OBJECT_CLASS(klass)->dispose = photo_native_plugin_dispose;
}

static void photo_native_plugin_init(PhotoNativePlugin *self) {
    self->textures_by_slot = g_hash_table_new_full(
        g_int64_hash, g_int64_equal, g_free, g_object_unref);
    self->engine = nullptr;
}

void photo_native_plugin_register_with_registrar(FlPluginRegistrar *registrar) {
    g_autoptr(PhotoNativePlugin) plugin = PHOTO_NATIVE_PLUGIN(
        g_object_new(photo_native_plugin_get_type(), nullptr));
    plugin->registrar = (FlPluginRegistrar *)g_object_ref(registrar);

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    plugin->channel = fl_method_channel_new(
        fl_plugin_registrar_get_messenger(registrar),
        "photo_native/texture_registry", FL_METHOD_CODEC(codec));

    fl_method_channel_set_method_call_handler(
        plugin->channel, method_call_cb, g_object_ref(plugin),
        g_object_unref);
}
