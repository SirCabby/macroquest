# Stub crashpad package for the MacroQuest Linux cross build. Provides the
# crashpad::crashpad target as a header-only no-op (see include/mq_crashpad_stub.h).
if(NOT TARGET crashpad::crashpad)
	add_library(crashpad::crashpad INTERFACE IMPORTED)
	set_target_properties(crashpad::crashpad PROPERTIES
		INTERFACE_INCLUDE_DIRECTORIES "${CMAKE_CURRENT_LIST_DIR}/include")
endif()
set(crashpad_FOUND TRUE)
