/*
 * MacroQuest: The extension platform for EverQuest
 * Copyright (C) 2002-present MacroQuest Authors
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License, version 2, as published by
 * the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */

/*
 * mq-tray-helper: native Linux StatusNotifierItem for the wine-hosted
 * MacroQuest loader.
 *
 * Wine tray icons are XEmbed windows; on Wayland desktops they are bridged by
 * an XEmbed->SNI proxy whose click forwarding does not survive the trip into
 * wine - the icon shows but never responds. This helper gives MacroQuest a
 * first-class panel presence instead: it registers a real StatusNotifierItem
 * on the session bus and exports the loader's tray menu as a native
 * com.canonical.dbusmenu (rendered by the panel itself, like any native tray
 * application).
 *
 * The menu content is streamed from the loader over a localhost TCP socket
 * (see the "Wine tray bridge" section in src/loader/MacroQuest.cpp):
 *
 *   loader -> helper:
 *     menu-reset\n
 *     menu-item <id> <parentId> <kind> <label>\n     kind: i=item, s=separator, h=disabled header
 *     menu-commit\n                                  (helper emits LayoutUpdated)
 *
 *   helper -> loader:
 *     activate\n                (left click / SNI Activate)
 *     menuitem <id>\n           (menu item clicked)
 *     abouttoshow\n             (menu about to open; loader refreshes the model)
 *     contextmenu <x> <y>\n     (SNI ContextMenu call from menu-less hosts)
 *     exit\n                    (builtin fallback exit item)
 *
 * Until the loader pushes a model, a minimal builtin menu (Open UI / Exit) is
 * served. The helper exits when the socket closes (loader shutdown) or when
 * it cannot register with a StatusNotifierWatcher.
 *
 * Spawned by the loader as:  mq-tray-helper <port> [title]
 */

#include <systemd/sd-bus.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "mq_tray_icon.h"

static int g_sock = -1;
static const char* g_title = "MacroQuest";
static sd_bus* g_bus = NULL;

static void send_line(const char* line)
{
	if (g_sock >= 0)
		send(g_sock, line, strlen(line), MSG_NOSIGNAL);
}

/* ------------------------------------------------------------------------- */
/* Menu model                                                                */
/* ------------------------------------------------------------------------- */

struct menu_item
{
	int id;
	int parent;
	char kind;                 /* 'i' item, 's' separator, 'h' disabled header */
	char* label;
	const char* builtin_line;  /* builtin items send this instead of "menuitem <id>" */
};

static struct menu_item* g_items = NULL;
static size_t g_item_count = 0;
static size_t g_item_capacity = 0;
static unsigned g_revision = 1;

/* items being accumulated between menu-reset and menu-commit */
static struct menu_item* g_pending = NULL;
static size_t g_pending_count = 0;
static size_t g_pending_capacity = 0;

static void item_list_free(struct menu_item** items, size_t* count, size_t* capacity)
{
	for (size_t i = 0; i < *count; ++i)
		free((*items)[i].label);
	free(*items);
	*items = NULL;
	*count = 0;
	*capacity = 0;
}

static void item_list_add(struct menu_item** items, size_t* count, size_t* capacity,
	int id, int parent, char kind, const char* label, const char* builtinLine)
{
	if (*count == *capacity)
	{
		size_t newCapacity = *capacity == 0 ? 32 : *capacity * 2;
		struct menu_item* grown = realloc(*items, newCapacity * sizeof(struct menu_item));
		if (grown == NULL)
			return;
		*items = grown;
		*capacity = newCapacity;
	}

	struct menu_item* item = &(*items)[(*count)++];
	item->id = id;
	item->parent = parent;
	item->kind = kind;
	item->label = strdup(label != NULL ? label : "");
	item->builtin_line = builtinLine;
}

static const struct menu_item* find_menu_item(int id)
{
	for (size_t i = 0; i < g_item_count; ++i)
		if (g_items[i].id == id)
			return &g_items[i];
	return NULL;
}

static int item_has_children(int id)
{
	for (size_t i = 0; i < g_item_count; ++i)
		if (g_items[i].parent == id)
			return 1;
	return 0;
}

static void install_builtin_menu(void)
{
	item_list_free(&g_items, &g_item_count, &g_item_capacity);
	item_list_add(&g_items, &g_item_count, &g_item_capacity, 1, 0, 'i', "Open UI", "activate\n");
	item_list_add(&g_items, &g_item_count, &g_item_capacity, 2, 0, 's', "", NULL);
	item_list_add(&g_items, &g_item_count, &g_item_capacity, 3, 0, 'i', "Exit MacroQuest", "exit\n");
}

static void menu_item_clicked(int id)
{
	const struct menu_item* item = find_menu_item(id);
	if (item == NULL)
		return;

	if (item->builtin_line != NULL)
	{
		send_line(item->builtin_line);
	}
	else
	{
		char line[32];
		snprintf(line, sizeof(line), "menuitem %d\n", item->id);
		send_line(line);
	}
}

/* ------------------------------------------------------------------------- */
/* com.canonical.dbusmenu                                                    */
/* ------------------------------------------------------------------------- */

static int append_dict_entry_str(sd_bus_message* reply, const char* key, const char* value)
{
	int r = sd_bus_message_open_container(reply, 'e', "sv");
	if (r < 0) return r;
	r = sd_bus_message_append(reply, "s", key);
	if (r < 0) return r;
	r = sd_bus_message_append(reply, "v", "s", value);
	if (r < 0) return r;
	return sd_bus_message_close_container(reply);
}

static int append_dict_entry_bool(sd_bus_message* reply, const char* key, int value)
{
	int r = sd_bus_message_open_container(reply, 'e', "sv");
	if (r < 0) return r;
	r = sd_bus_message_append(reply, "s", key);
	if (r < 0) return r;
	r = sd_bus_message_append(reply, "v", "b", value);
	if (r < 0) return r;
	return sd_bus_message_close_container(reply);
}

static int append_item_props(sd_bus_message* reply, const struct menu_item* item)
{
	int r = sd_bus_message_open_container(reply, 'a', "{sv}");
	if (r < 0) return r;

	if (item->kind == 's')
	{
		r = append_dict_entry_str(reply, "type", "separator");
		if (r < 0) return r;
	}
	else
	{
		r = append_dict_entry_str(reply, "label", item->label);
		if (r < 0) return r;
		if (item->kind == 'h')
		{
			r = append_dict_entry_bool(reply, "enabled", 0);
			if (r < 0) return r;
		}
		if (item_has_children(item->id))
		{
			r = append_dict_entry_str(reply, "children-display", "submenu");
			if (r < 0) return r;
		}
	}

	return sd_bus_message_close_container(reply);
}

/* Append one (ia{sv}av) item struct including its subtree. */
static int append_item_struct(sd_bus_message* reply, int id)
{
	int r = sd_bus_message_open_container(reply, 'r', "ia{sv}av");
	if (r < 0) return r;
	r = sd_bus_message_append(reply, "i", id);
	if (r < 0) return r;

	if (id == 0)
	{
		r = sd_bus_message_open_container(reply, 'a', "{sv}");
		if (r < 0) return r;
		r = append_dict_entry_str(reply, "children-display", "submenu");
		if (r < 0) return r;
		r = sd_bus_message_close_container(reply);
		if (r < 0) return r;
	}
	else
	{
		const struct menu_item* item = find_menu_item(id);
		static const struct menu_item empty = { 0, 0, 'i', "", NULL };
		struct menu_item labeled = empty;
		if (item != NULL)
			labeled = *item;
		r = append_item_props(reply, &labeled);
		if (r < 0) return r;
	}

	r = sd_bus_message_open_container(reply, 'a', "v");
	if (r < 0) return r;
	for (size_t i = 0; i < g_item_count; ++i)
	{
		if (g_items[i].parent != id)
			continue;
		r = sd_bus_message_open_container(reply, 'v', "(ia{sv}av)");
		if (r < 0) return r;
		r = append_item_struct(reply, g_items[i].id);
		if (r < 0) return r;
		r = sd_bus_message_close_container(reply);
		if (r < 0) return r;
	}
	r = sd_bus_message_close_container(reply);
	if (r < 0) return r;

	return sd_bus_message_close_container(reply);
}

static int menu_get_layout(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	int parentId = 0, depth = -1;
	sd_bus_message_read(m, "ii", &parentId, &depth);

	sd_bus_message* reply = NULL;
	int r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) return r;

	sd_bus_message_append(reply, "u", g_revision);
	append_item_struct(reply, parentId);

	r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	return r < 0 ? r : 1;
}

static int menu_get_group_properties(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;

	int requested[256];
	int requestedCount = 0;

	if (sd_bus_message_enter_container(m, 'a', "i") >= 0)
	{
		int id;
		while (sd_bus_message_read_basic(m, 'i', &id) > 0)
		{
			if (requestedCount < (int)(sizeof(requested) / sizeof(requested[0])))
				requested[requestedCount++] = id;
		}
		sd_bus_message_exit_container(m);
	}

	sd_bus_message* reply = NULL;
	int r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) return r;

	sd_bus_message_open_container(reply, 'a', "(ia{sv})");
	for (size_t i = 0; i < g_item_count; ++i)
	{
		if (requestedCount > 0)
		{
			int wanted = 0;
			for (int j = 0; j < requestedCount; ++j)
				if (requested[j] == g_items[i].id)
					wanted = 1;
			if (!wanted)
				continue;
		}
		sd_bus_message_open_container(reply, 'r', "ia{sv}");
		sd_bus_message_append(reply, "i", g_items[i].id);
		append_item_props(reply, &g_items[i]);
		sd_bus_message_close_container(reply);
	}
	sd_bus_message_close_container(reply);

	r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	return r < 0 ? r : 1;
}

static int menu_get_property(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	int id = 0;
	const char* name = NULL;
	sd_bus_message_read(m, "is", &id, &name);

	const struct menu_item* item = find_menu_item(id);
	const char* value = "";
	if (item != NULL && name != NULL)
	{
		if (strcmp(name, "label") == 0)
			value = item->label;
		else if (strcmp(name, "type") == 0 && item->kind == 's')
			value = "separator";
	}

	sd_bus_message* reply = NULL;
	int r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) return r;
	sd_bus_message_append(reply, "v", "s", value);
	r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	return r < 0 ? r : 1;
}

static int menu_event(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	int id = 0;
	const char* eventId = NULL;
	if (sd_bus_message_read(m, "is", &id, &eventId) >= 0
		&& eventId != NULL && strcmp(eventId, "clicked") == 0)
	{
		menu_item_clicked(id);
	}
	return sd_bus_reply_method_return(m, "");
}

static int menu_event_group(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;

	if (sd_bus_message_enter_container(m, 'a', "(isvu)") >= 0)
	{
		for (;;)
		{
			int r = sd_bus_message_enter_container(m, 'r', "isvu");
			if (r <= 0)
				break;
			int id = 0;
			const char* eventId = NULL;
			sd_bus_message_read(m, "is", &id, &eventId);
			sd_bus_message_skip(m, "vu");
			sd_bus_message_exit_container(m);
			if (eventId != NULL && strcmp(eventId, "clicked") == 0)
				menu_item_clicked(id);
		}
		sd_bus_message_exit_container(m);
	}

	sd_bus_message* reply = NULL;
	int r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) return r;
	sd_bus_message_open_container(reply, 'a', "i");
	sd_bus_message_close_container(reply);
	r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	return r < 0 ? r : 1;
}

static int menu_about_to_show(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	int id = 0;
	sd_bus_message_read(m, "i", &id);
	if (id == 0)
		send_line("abouttoshow\n"); /* loader refreshes + pushes the model */
	return sd_bus_reply_method_return(m, "b", 0);
}

static int menu_about_to_show_group(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	send_line("abouttoshow\n");

	sd_bus_message* reply = NULL;
	int r = sd_bus_message_new_method_return(m, &reply);
	if (r < 0) return r;
	sd_bus_message_open_container(reply, 'a', "i");
	sd_bus_message_close_container(reply);
	sd_bus_message_open_container(reply, 'a', "i");
	sd_bus_message_close_container(reply);
	r = sd_bus_send(NULL, reply, NULL);
	sd_bus_message_unref(reply);
	return r < 0 ? r : 1;
}

static int menu_prop_get(sd_bus* bus, const char* path, const char* interface,
	const char* property, sd_bus_message* reply, void* userdata, sd_bus_error* error)
{
	(void)bus; (void)path; (void)interface; (void)userdata; (void)error;

	if (strcmp(property, "Version") == 0)
		return sd_bus_message_append(reply, "u", 3);
	if (strcmp(property, "Status") == 0)
		return sd_bus_message_append(reply, "s", "normal");
	if (strcmp(property, "TextDirection") == 0)
		return sd_bus_message_append(reply, "s", "ltr");
	if (strcmp(property, "IconThemePath") == 0)
	{
		int r = sd_bus_message_open_container(reply, 'a', "s");
		if (r < 0) return r;
		return sd_bus_message_close_container(reply);
	}
	return -EINVAL;
}

static const sd_bus_vtable menu_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("GetLayout", "iias", "u(ia{sv}av)", menu_get_layout, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("GetGroupProperties", "aias", "a(ia{sv})", menu_get_group_properties, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("GetProperty", "is", "v", menu_get_property, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Event", "isvu", "", menu_event, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("EventGroup", "a(isvu)", "ai", menu_event_group, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("AboutToShow", "i", "b", menu_about_to_show, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("AboutToShowGroup", "ai", "aiai", menu_about_to_show_group, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_PROPERTY("Version", "u", menu_prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("Status", "s", menu_prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("TextDirection", "s", menu_prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("IconThemePath", "as", menu_prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_SIGNAL("LayoutUpdated", "ui", 0),
	SD_BUS_SIGNAL("ItemsPropertiesUpdated", "a(ia{sv})a(ias)", 0),
	SD_BUS_VTABLE_END
};

/* ------------------------------------------------------------------------- */
/* Socket protocol (loader -> helper)                                        */
/* ------------------------------------------------------------------------- */

static void handle_loader_line(char* line)
{
	if (strcmp(line, "menu-reset") == 0)
	{
		item_list_free(&g_pending, &g_pending_count, &g_pending_capacity);
	}
	else if (strncmp(line, "menu-item ", 10) == 0)
	{
		int id = 0, parent = 0;
		char kind = 'i';
		int consumed = 0;
		if (sscanf(line + 10, "%d %d %c %n", &id, &parent, &kind, &consumed) >= 3)
		{
			const char* label = line + 10 + consumed;
			item_list_add(&g_pending, &g_pending_count, &g_pending_capacity,
				id, parent, kind, label, NULL);
		}
	}
	else if (strcmp(line, "menu-commit") == 0)
	{
		item_list_free(&g_items, &g_item_count, &g_item_capacity);
		g_items = g_pending;
		g_item_count = g_pending_count;
		g_item_capacity = g_pending_capacity;
		g_pending = NULL;
		g_pending_count = 0;
		g_pending_capacity = 0;

		++g_revision;
		if (g_bus != NULL)
			sd_bus_emit_signal(g_bus, "/MenuBar", "com.canonical.dbusmenu",
				"LayoutUpdated", "ui", g_revision, 0);
	}
}

/* Returns 0 when the loader connection was lost. */
static int drain_loader_socket(void)
{
	static char buffer[16384];
	static size_t buffered = 0;

	ssize_t received = recv(g_sock, buffer + buffered, sizeof(buffer) - buffered - 1, 0);
	if (received <= 0)
		return 0;
	buffered += (size_t)received;
	buffer[buffered] = '\0';

	char* start = buffer;
	for (;;)
	{
		char* newline = strchr(start, '\n');
		if (newline == NULL)
			break;
		*newline = '\0';
		handle_loader_line(start);
		start = newline + 1;
	}

	buffered = (size_t)(buffer + buffered - start);
	memmove(buffer, start, buffered);
	return 1;
}

/* ------------------------------------------------------------------------- */
/* org.kde.StatusNotifierItem                                                */
/* ------------------------------------------------------------------------- */

static int method_context_menu(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	int x = 0, y = 0;
	sd_bus_message_read(m, "ii", &x, &y);

	char line[64];
	snprintf(line, sizeof(line), "contextmenu %d %d\n", x, y);
	send_line(line);
	return sd_bus_reply_method_return(m, "");
}

static int method_activate(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	send_line("activate\n");
	return sd_bus_reply_method_return(m, "");
}

static int method_scroll(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)userdata; (void)error;
	return sd_bus_reply_method_return(m, "");
}

static int prop_get(sd_bus* bus, const char* path, const char* interface,
	const char* property, sd_bus_message* reply, void* userdata, sd_bus_error* error)
{
	(void)bus; (void)path; (void)interface; (void)userdata; (void)error;

	if (strcmp(property, "Category") == 0)
		return sd_bus_message_append(reply, "s", "ApplicationStatus");
	if (strcmp(property, "Id") == 0)
		return sd_bus_message_append(reply, "s", "MacroQuest");
	if (strcmp(property, "Title") == 0)
		return sd_bus_message_append(reply, "s", g_title);
	if (strcmp(property, "Status") == 0)
		return sd_bus_message_append(reply, "s", "Active");
	if (strcmp(property, "IconName") == 0 || strcmp(property, "IconThemePath") == 0)
		return sd_bus_message_append(reply, "s", "");
	if (strcmp(property, "WindowId") == 0)
		return sd_bus_message_append(reply, "i", 0);
	if (strcmp(property, "ItemIsMenu") == 0)
		return sd_bus_message_append(reply, "b", 0);
	if (strcmp(property, "Menu") == 0)
		return sd_bus_message_append(reply, "o", "/MenuBar");

	if (strcmp(property, "IconPixmap") == 0)
	{
		int r = sd_bus_message_open_container(reply, 'a', "(iiay)");
		if (r < 0) return r;
		r = sd_bus_message_open_container(reply, 'r', "iiay");
		if (r < 0) return r;
		r = sd_bus_message_append(reply, "ii", MQ_TRAY_ICON_WIDTH, MQ_TRAY_ICON_HEIGHT);
		if (r < 0) return r;
		r = sd_bus_message_append_array(reply, 'y', mq_tray_icon_argb, sizeof(mq_tray_icon_argb));
		if (r < 0) return r;
		r = sd_bus_message_close_container(reply);
		if (r < 0) return r;
		return sd_bus_message_close_container(reply);
	}

	if (strcmp(property, "ToolTip") == 0)
	{
		int r = sd_bus_message_open_container(reply, 'r', "sa(iiay)ss");
		if (r < 0) return r;
		r = sd_bus_message_append(reply, "s", "");
		if (r < 0) return r;
		r = sd_bus_message_open_container(reply, 'a', "(iiay)");
		if (r < 0) return r;
		r = sd_bus_message_close_container(reply);
		if (r < 0) return r;
		r = sd_bus_message_append(reply, "ss", g_title, "");
		if (r < 0) return r;
		return sd_bus_message_close_container(reply);
	}

	return -EINVAL;
}

static const sd_bus_vtable sni_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("ContextMenu", "ii", "", method_context_menu, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Activate", "ii", "", method_activate, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("SecondaryActivate", "ii", "", method_activate, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("Scroll", "is", "", method_scroll, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_PROPERTY("Category", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("Id", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("Title", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("Status", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("IconName", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("IconThemePath", "s", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("IconPixmap", "a(iiay)", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("ToolTip", "(sa(iiay)ss)", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("WindowId", "i", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("ItemIsMenu", "b", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_PROPERTY("Menu", "o", prop_get, 0, SD_BUS_VTABLE_PROPERTY_CONST),
	SD_BUS_VTABLE_END
};

static int register_with_watcher(sd_bus* bus, const char* busName)
{
	sd_bus_error error = SD_BUS_ERROR_NULL;
	int r = sd_bus_call_method(bus,
		"org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
		"org.kde.StatusNotifierWatcher", "RegisterStatusNotifierItem",
		&error, NULL, "s", busName);
	if (r < 0)
		fprintf(stderr, "mq-tray-helper: RegisterStatusNotifierItem failed: %s\n",
			error.message ? error.message : strerror(-r));
	sd_bus_error_free(&error);
	return r;
}

struct watcher_ctx
{
	sd_bus* bus;
	const char* busName;
};

/* Re-register when the StatusNotifierWatcher (plasmashell/kded) restarts. */
static int on_watcher_owner_changed(sd_bus_message* m, void* userdata, sd_bus_error* error)
{
	(void)error;
	struct watcher_ctx* ctx = userdata;
	const char *name = NULL, *oldOwner = NULL, *newOwner = NULL;
	if (sd_bus_message_read(m, "sss", &name, &oldOwner, &newOwner) >= 0
		&& newOwner != NULL && newOwner[0] != '\0')
	{
		register_with_watcher(ctx->bus, ctx->busName);
	}
	return 0;
}

int main(int argc, char** argv)
{
	if (argc < 2)
	{
		fprintf(stderr, "usage: mq-tray-helper <port> [title]\n");
		return 2;
	}
	int port = atoi(argv[1]);
	if (argc > 2)
		g_title = argv[2];

	signal(SIGPIPE, SIG_IGN);
	install_builtin_menu();

	/* Connect back to the loader */
	g_sock = socket(AF_INET, SOCK_STREAM, 0);
	struct sockaddr_in addr = {0};
	addr.sin_family = AF_INET;
	addr.sin_port = htons((unsigned short)port);
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(g_sock, (struct sockaddr*)&addr, sizeof(addr)) != 0)
	{
		fprintf(stderr, "mq-tray-helper: cannot connect to loader on port %d\n", port);
		return 1;
	}

	if (sd_bus_open_user(&g_bus) < 0)
	{
		fprintf(stderr, "mq-tray-helper: cannot connect to session bus\n");
		return 1;
	}

	sd_bus_slot* sniSlot = NULL;
	sd_bus_slot* menuSlot = NULL;
	if (sd_bus_add_object_vtable(g_bus, &sniSlot, "/StatusNotifierItem",
			"org.kde.StatusNotifierItem", sni_vtable, NULL) < 0
		|| sd_bus_add_object_vtable(g_bus, &menuSlot, "/MenuBar",
			"com.canonical.dbusmenu", menu_vtable, NULL) < 0)
	{
		fprintf(stderr, "mq-tray-helper: cannot export objects\n");
		return 1;
	}

	/* Well-known name per the SNI convention */
	static char busName[64];
	snprintf(busName, sizeof(busName), "org.kde.StatusNotifierItem-%d-1", (int)getpid());
	if (sd_bus_request_name(g_bus, busName, 0) < 0)
	{
		fprintf(stderr, "mq-tray-helper: cannot acquire bus name %s\n", busName);
		return 1;
	}

	static struct watcher_ctx ctx;
	ctx.bus = g_bus;
	ctx.busName = busName;
	sd_bus_add_match(g_bus, NULL,
		"type='signal',sender='org.freedesktop.DBus',path='/org/freedesktop/DBus',"
		"interface='org.freedesktop.DBus',member='NameOwnerChanged',"
		"arg0='org.kde.StatusNotifierWatcher'",
		on_watcher_owner_changed, &ctx);

	if (register_with_watcher(g_bus, busName) < 0)
		return 1;

	for (;;)
	{
		int r;
		while ((r = sd_bus_process(g_bus, NULL)) > 0)
			;
		if (r < 0)
			break;

		uint64_t timeoutUsec = UINT64_MAX;
		sd_bus_get_timeout(g_bus, &timeoutUsec);

		struct pollfd fds[2];
		fds[0].fd = sd_bus_get_fd(g_bus);
		fds[0].events = (short)sd_bus_get_events(g_bus);
		fds[0].revents = 0;
		fds[1].fd = g_sock;
		fds[1].events = POLLIN;
		fds[1].revents = 0;

		int timeoutMs = -1;
		if (timeoutUsec != UINT64_MAX)
			timeoutMs = (int)(timeoutUsec > 60u * 1000 * 1000 ? 60000 : timeoutUsec / 1000);

		if (poll(fds, 2, timeoutMs) < 0)
			break;

		if (fds[1].revents != 0)
		{
			if (!drain_loader_socket())
				break; /* loader went away */
		}
	}

	sd_bus_unref(g_bus);
	close(g_sock);
	return 0;
}
