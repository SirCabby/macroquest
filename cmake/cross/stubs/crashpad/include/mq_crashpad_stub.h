// ============================================================================
// Stub Crashpad API for the MacroQuest Linux cross build.
// ============================================================================
// Crashpad is a GN/mini_chromium build that is impractical to cross-compile
// with clang-cl. It only provides crash reporting, which is non-essential, so
// this header set satisfies the exact API surface used by src/main/CrashHandler.cpp
// (and MacroQuest.cpp) with inert no-op implementations. All crash-reporting
// paths simply do nothing / report "not started".
#pragma once

#include <cstddef>
#include <cstdint>
#include <ctime>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace base {

class StringPiece
{
public:
	StringPiece() = default;
	StringPiece(const char*) {}
	StringPiece(const std::string&) {}
};

class FilePath
{
public:
	FilePath() = default;
	FilePath(const std::wstring&) {}
	FilePath(const std::string&) {}
};

} // namespace base

namespace crashpad {

struct UUID
{
	UUID() = default;
	void InitializeWithNew() {}
	std::string ToString() const { return std::string(); }
};

template <std::size_t N>
class StringAnnotation
{
public:
	explicit StringAnnotation(const char* /*name*/) {}
	void Set(base::StringPiece /*value*/) {}
	void Clear() {}
};

class Settings
{
public:
	void SetUploadsEnabled(bool) {}
	bool GetUploadsEnabled(bool* enabled)
	{
		if (enabled) *enabled = false;
		return false;
	}
	bool GetClientID(UUID*) { return false; }
};

class CrashReportDatabase
{
public:
	// Report metadata surface used by the loader's crash-report UI
	// (src/loader/Crashpad.cpp).
	struct Report
	{
		UUID uuid;
		time_t creation_time = 0;
		bool uploaded = false;
		time_t last_upload_attempt_time = 0;
		int upload_attempts = 0;
		bool upload_explicitly_requested = false;
		uint64_t total_size = 0;
	};

	enum OperationStatus
	{
		kNoError = 0,
		kDatabaseError,
	};

	Settings* GetSettings() { return &m_settings; }
	OperationStatus GetPendingReports(std::vector<Report>*) { return kNoError; }
	OperationStatus GetCompletedReports(std::vector<Report>*) { return kNoError; }
	OperationStatus RequestUpload(const UUID&) { return kNoError; }
	OperationStatus DeleteReport(const UUID&) { return kNoError; }
	static std::unique_ptr<CrashReportDatabase> Initialize(const base::FilePath&) { return nullptr; }

private:
	Settings m_settings;
};

class CrashpadClient
{
public:
	CrashpadClient() = default;

	// Real signature takes (handler, database, metrics, url, annotations,
	// arguments, restartable, asynchronous_start); accept anything.
	template <typename... Args>
	bool StartHandler(Args&&...) { return false; }

	bool WaitForHandlerStart(unsigned int /*timeout_ms*/) { return false; }
	bool SetHandlerIPCPipe(const std::wstring&) { return false; }
	std::wstring GetHandlerIPCPipe() const { return std::wstring(); }

	template <typename T>
	static void DumpWithoutCrash(T&&) {}
};

// CaptureContext(&CONTEXT) — templated so we don't need <windows.h> here.
template <typename T>
inline void CaptureContext(T* /*context*/) {}

// crashpad_info.h surface (included but unused by MacroQuest).
class CrashpadInfo
{
public:
	static CrashpadInfo* GetCrashpadInfo() { static CrashpadInfo info; return &info; }
};

} // namespace crashpad
