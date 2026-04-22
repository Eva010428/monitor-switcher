#include <windows.h>
#include <PhysicalMonitorEnumerationAPI.h>
#include <LowLevelMonitorConfigurationAPI.h>
#include <iostream>
#include <vector>
#include <string>
#include <unordered_map>
#include <functional>
#include <sstream>
#include <fstream>
#include <regex>

#include "json.hpp"
using json = nlohmann::json;

std::vector<PHYSICAL_MONITOR> physicalMonitors{};

BOOL CALLBACK monitorEnumProcCallback(HMONITOR hMonitor, HDC hDeviceContext, LPRECT rect, LPARAM data)
{
	DWORD numberOfPhysicalMonitors;
	BOOL success = GetNumberOfPhysicalMonitorsFromHMONITOR(hMonitor, &numberOfPhysicalMonitors);
	if (success) {
		auto originalSize = physicalMonitors.size();
		physicalMonitors.resize(physicalMonitors.size() + numberOfPhysicalMonitors);
		success = GetPhysicalMonitorsFromHMONITOR(hMonitor, numberOfPhysicalMonitors, physicalMonitors.data() + originalSize);
	}
	return true;
}

std::string toUtf8(const wchar_t *buffer)
{
	if (!buffer) return {};
	int len = WideCharToMultiByte(CP_UTF8, 0, buffer, -1, nullptr, 0, nullptr, nullptr);
	if (len <= 0) return {};
	std::string result(len - 1, '\0');
	WideCharToMultiByte(CP_UTF8, 0, buffer, -1, &result[0], len, nullptr, nullptr);
	return result;
}

int printUsage(std::vector<std::string> args)
{
	std::cout << "Monitor Switcher - DDC/CI Control Tool" << std::endl;
	std::cout << "=======================================" << std::endl << std::endl;
	std::cout << "Usage: monitor_switcher <command> [<arg> ...]" << std::endl << std::endl;
	std::cout << "High-level Commands:" << std::endl;
	std::cout << "  switch <profile>                               Switch monitors to profile (windows|mac)" << std::endl;
	std::cout << "  setup                                          Run interactive setup wizard" << std::endl;
	std::cout << std::endl;
	std::cout << "Low-level Commands:" << std::endl;
	std::cout << "  help                                           Display help" << std::endl;
	std::cout << "  detect                                         Detect monitors" << std::endl;
	std::cout << "  capabilities <display-id>                      Query monitor capabilities" << std::endl;
	std::cout << "  getvcp <display-id> <feature-code>             Report VCP feature value" << std::endl;
	std::cout << "  setvcp <display-id> <feature-code> <new-value> Set VCP feature value" << std::endl;
	std::cout << std::endl;
	std::cout << "Examples:" << std::endl;
	std::cout << "  monitor_switcher setup                         Run setup wizard" << std::endl;
	std::cout << "  monitor_switcher switch mac                    Switch to Mac" << std::endl;
	std::cout << "  monitor_switcher switch windows                Switch to Windows" << std::endl;
	std::cout << "  monitor_switcher detect                        List all monitors" << std::endl;
	std::cout << "  monitor_switcher getvcp 0 60                   Get input source for monitor 0" << std::endl;
	std::cout << "  monitor_switcher setvcp 0 60 15                Set monitor 0 to DisplayPort (15)" << std::endl;
	return 1;
}

int detect(std::vector<std::string> args)
{
	std::cout << "Detected Monitors:" << std::endl;
	std::cout << "------------------" << std::endl;
	int i = 0;
	for (auto &physicalMonitor : physicalMonitors) {
		std::cout << "Display " << i << ":\t" << toUtf8(physicalMonitor.szPhysicalMonitorDescription) << std::endl;
		i++;
	}
	std::cout << std::endl;
	std::cout << "Tip: Use 'getvcp <display-id> 60' to check current input source" << std::endl;
	return 0;
}

int capabilities(std::vector<std::string> args) {
	if (args.size() < 1) {
		std::cerr << "Display ID required" << std::endl;
		return printUsage(args);
	}

	size_t displayId = INT_MAX;
	try {
		displayId = std::stoi(args[0]);
	}
	catch (...) {
		std::cerr << "Failed to parse display ID" << std::endl;
		return 1;
	}

	if (displayId > physicalMonitors.size() - 1) {
		std::cerr << "Invalid display ID" << std::endl;
		return 1;
	}

	auto physicalMonitorHandle = physicalMonitors[displayId].hPhysicalMonitor;

	DWORD capabilitiesStringLengthInCharacters;
	auto success = GetCapabilitiesStringLength(physicalMonitorHandle, &capabilitiesStringLengthInCharacters);
	if (!success) {
		std::cerr << "Failed to get capabilities string length" << std::endl;
		return 1;
	}

	std::unique_ptr<char[]> capabilitiesString{ new char[capabilitiesStringLengthInCharacters] };
	success = CapabilitiesRequestAndCapabilitiesReply(physicalMonitorHandle, capabilitiesString.get(), capabilitiesStringLengthInCharacters);
	if (!success) {
		std::cerr << "Failed to get capabilities string" << std::endl;
		return 1;
	}

	std::cout << std::string(capabilitiesString.get()) << std::endl;

	return 0;
}

int getVcp(std::vector<std::string> args) {
	if (args.size() < 2) {
		std::cerr << "Display ID and VCP code required" << std::endl;
		return printUsage(args);
	}

	size_t displayId = INT_MAX;
	BYTE vcpCode;
	try {
		displayId = std::stoi(args[0]);
		vcpCode = std::stoul(args[1], nullptr, 16);
	}
	catch (...) {
		std::cerr << "Failed to parse display ID or VCP code" << std::endl;
		return 1;
	}

	if (displayId > physicalMonitors.size() - 1) {
		std::cerr << "Invalid display ID" << std::endl;
		return 1;
	}

	auto physicalMonitorHandle = physicalMonitors[displayId].hPhysicalMonitor;

	DWORD currentValue;
	bool success = GetVCPFeatureAndVCPFeatureReply(physicalMonitorHandle, vcpCode, NULL, &currentValue, NULL);
	if (!success) {
		std::cerr << "Failed to get the vcp code value" << std::endl;
		return 1;
	}

	std::stringstream ss;
	ss << std::hex << currentValue;
	std::cout << "VCP " << args[1] << " = 0x" << ss.str() << " (" << currentValue << " decimal)" << std::endl;

	return 0;
}

int setVcp(std::vector<std::string> args) {
	if (args.size() < 3) {
		std::cerr << "Invalid number of arguments" << std::endl;
		return printUsage(args);
	}

	size_t displayId = INT_MAX;
	BYTE vcpCode;
	DWORD newValue;
	try {
		displayId = std::stoi(args[0]);
		vcpCode = std::stoul(args[1], nullptr, 16);
		newValue = std::stoul(args[2], nullptr, 0);
	}
	catch (...) {
		std::cerr << "Failed to parse setvcp arguments" << std::endl;
		return printUsage(args);
	}

	if (displayId > physicalMonitors.size() - 1) {
		std::cerr << "Invalid display ID" << std::endl;
		return 1;
	}

	bool success = SetVCPFeature(physicalMonitors[displayId].hPhysicalMonitor, vcpCode, newValue);
	if (!success) {
		std::cerr << "Failed to set vcp feature for display " << displayId << std::endl;
		return 1;
	}

	std::cout << "Successfully set display " << displayId << " VCP 0x" << std::hex << (int)vcpCode
	          << " to " << std::dec << newValue << std::endl;

	return 0;
}

struct Config {
	int vcpCode = 0x60;
	std::unordered_map<std::string, int> inputs = {{"dp1", 15}, {"hdmi2", 18}};
	// Per-monitor profile mapping: profile_name -> { monitor_id -> input_name }
	// monitor_id == -1 means "all monitors" (backward compat with old string format)
	std::unordered_map<std::string, std::unordered_map<int, std::string>> profiles = {
		{"windows", {{-1, "dp1"}}},
		{"mac", {{-1, "hdmi2"}}}
	};
};

std::string getConfigPath() {
	char exePath[MAX_PATH];
	GetModuleFileNameA(NULL, exePath, MAX_PATH);
	std::string path(exePath);
	auto lastSlash = path.find_last_of("\\/");
	if (lastSlash != std::string::npos)
		path = path.substr(0, lastSlash);
	return path + "\\..\\config\\monitors.json";
}

Config loadConfig() {
	Config config;
	std::string configPath = getConfigPath();
	try {
		std::ifstream configFile(configPath);
		if (!configFile.is_open()) {
			std::cerr << "Warning: Config not found at " << configPath << std::endl;
			std::cerr << "         Using hardcoded defaults (DP1=15, HDMI2=18)." << std::endl;
			std::cerr << "         Run 'monitor_switcher setup' to auto-configure." << std::endl;
			return config;
		}
		json j = json::parse(configFile);
		if (j.contains("vcp_code") && j["vcp_code"].is_string())
			config.vcpCode = (int)std::stoul(j["vcp_code"].get<std::string>(), nullptr, 16);
		if (j.contains("inputs"))
			for (auto& [key, val] : j["inputs"].items())
				if (val.is_number_integer()) config.inputs[key] = val.get<int>();
		if (j.contains("profiles"))
			for (auto& [key, val] : j["profiles"].items()) {
				if (val.is_string()) {
					// Old format: single input name for all monitors
					config.profiles[key] = {{-1, val.get<std::string>()}};
				} else if (val.is_object()) {
					// New format: per-monitor mapping { "0": "dp1", "1": "hdmi2" }
					std::unordered_map<int, std::string> monMap;
					for (auto& [mid, iname] : val.items()) {
						if (iname.is_string()) {
							try { monMap[std::stoi(mid)] = iname.get<std::string>(); }
							catch (...) {}
						}
					}
					config.profiles[key] = monMap;
				}
			}
	} catch (const std::exception& e) {
		std::cerr << "Warning: Failed to parse config (" << e.what() << "), using defaults." << std::endl;
	}
	return config;
}

int switchProfile(std::vector<std::string> args) {
	if (args.size() < 1) {
		std::cerr << "Profile name required (windows|mac)" << std::endl;
		return printUsage(args);
	}

	std::string profileName = args[0];
	Config config = loadConfig();

	if (config.profiles.find(profileName) == config.profiles.end()) {
		std::cerr << "Unknown profile: " << profileName << std::endl;
		std::cerr << "Available profiles: ";
		for (const auto& [key, value] : config.profiles) {
			std::cerr << key << " ";
		}
		std::cerr << std::endl;
		return 1;
	}

	auto& monitorMap = config.profiles[profileName];

	std::cout << "Switching monitors to profile '" << profileName << "'" << std::endl;
	std::cout << std::endl;

	bool anySuccess = false;
	bool anyFailure = false;

	if (monitorMap.count(-1)) {
		// Legacy format: single input for all monitors
		std::string inputName = monitorMap[-1];
		if (config.inputs.find(inputName) == config.inputs.end()) {
			std::cerr << "Unknown input: " << inputName << std::endl;
			return 1;
		}
		int inputValue = config.inputs[inputName];
		std::cout << "  All monitors -> " << inputName << " (" << inputValue << ")" << std::endl;

		for (size_t i = 0; i < physicalMonitors.size(); i++) {
			std::cout << "Display " << i << ": ";
			bool success = false;
			for (int retry = 0; retry < 3 && !success; retry++) {
				if (retry > 0) { Sleep(500); std::cout << "Retry " << retry << "... "; }
				success = SetVCPFeature(physicalMonitors[i].hPhysicalMonitor, config.vcpCode, inputValue);
			}
			std::cout << (success ? "OK" : "FAILED") << std::endl;
			if (success) anySuccess = true; else anyFailure = true;
		}
	} else {
		// Per-monitor mapping
		for (auto& [monId, inputName] : monitorMap) {
			if (monId < 0 || monId >= (int)physicalMonitors.size()) {
				std::cerr << "Display " << monId << ": skipped (not found)" << std::endl;
				anyFailure = true;
				continue;
			}
			if (config.inputs.find(inputName) == config.inputs.end()) {
				std::cerr << "Display " << monId << ": unknown input '" << inputName << "'" << std::endl;
				anyFailure = true;
				continue;
			}
			int inputValue = config.inputs[inputName];
			std::cout << "Display " << monId << " (" << inputName << " -> " << inputValue << "): ";

			bool success = false;
			for (int retry = 0; retry < 3 && !success; retry++) {
				if (retry > 0) { Sleep(500); std::cout << "Retry " << retry << "... "; }
				success = SetVCPFeature(physicalMonitors[monId].hPhysicalMonitor, config.vcpCode, inputValue);
			}
			std::cout << (success ? "OK" : "FAILED") << std::endl;
			if (success) anySuccess = true; else anyFailure = true;
		}
	}

	std::cout << std::endl;
	if (anySuccess && !anyFailure) {
		std::cout << "All monitors switched successfully!" << std::endl;
		return 0;
	} else if (anySuccess && anyFailure) {
		std::cout << "Some monitors failed to switch." << std::endl;
		return 2;
	} else {
		std::cout << "Failed to switch any monitor." << std::endl;
		return 1;
	}
}

// ─── Setup Wizard helpers ────────────────────────────────────────────────────

std::string getCapabilitiesString(size_t monitorIndex) {
	auto handle = physicalMonitors[monitorIndex].hPhysicalMonitor;
	DWORD len = 0;
	if (!GetCapabilitiesStringLength(handle, &len) || len == 0)
		return "";
	std::unique_ptr<char[]> buf{ new char[len] };
	if (!CapabilitiesRequestAndCapabilitiesReply(handle, buf.get(), len))
		return "";
	return std::string(buf.get());
}

std::vector<int> parseInputCodesFromCapabilities(const std::string& caps) {
	std::vector<int> codes;
	// Matches "60(0F 12)" or "60(0f 12 15)" in the vcp(...) section
	std::regex vcpRegex(R"(\b60\(([^)]+)\))");
	std::smatch match;
	if (std::regex_search(caps, match, vcpRegex)) {
		std::istringstream iss(match[1].str());
		std::string token;
		while (iss >> token) {
			try { codes.push_back((int)std::stoul(token, nullptr, 16)); }
			catch (...) {}
		}
	}
	return codes;
}

std::string knownInputName(int code) {
	static const std::unordered_map<int, std::string> known = {
		{3,  "DVI 1"}, {4,  "DVI 2"},
		{15, "DisplayPort 1"}, {16, "DisplayPort 2"},
		{17, "HDMI 1"}, {18, "HDMI 2"}, {19, "HDMI 3"},
		{27, "USB-C / DP"}
	};
	auto it = known.find(code);
	return (it != known.end()) ? it->second : "Unknown";
}

std::string autoInputKey(int code) {
	static const std::unordered_map<int, std::string> keys = {
		{3, "dvi1"}, {4, "dvi2"},
		{15, "dp1"}, {16, "dp2"},
		{17, "hdmi1"}, {18, "hdmi2"}, {19, "hdmi3"},
		{27, "usbc"}
	};
	auto it = keys.find(code);
	return (it != keys.end()) ? it->second : "input" + std::to_string(code);
}

void blinkMonitor(HANDLE hMonitor, size_t displayIdx, int times = 5) {
	DWORD originalBrightness = 50;
	GetVCPFeatureAndVCPFeatureReply(hMonitor, 0x10, NULL, &originalBrightness, NULL);
	std::cout << "  Blinking display " << displayIdx << std::flush;
	for (int i = 0; i < times; i++) {
		SetVCPFeature(hMonitor, 0x10, 5);
		Sleep(400);
		SetVCPFeature(hMonitor, 0x10, originalBrightness);
		Sleep(400);
		std::cout << "." << std::flush;
	}
	std::cout << " done" << std::endl;
}

void writeConfig(const std::string& configPath,
                 const std::vector<std::pair<std::string, int>>& inputs,
                 size_t monitorCount,
                 const std::vector<std::string>& monitorNames,
                 const std::unordered_map<std::string, std::unordered_map<int, std::string>>& profiles) {
	json j;
	j["vcp_code"] = "0x60";

	j["monitors"] = json::array();
	for (size_t i = 0; i < monitorCount; i++)
		j["monitors"].push_back({{"id", (int)i}, {"name", monitorNames[i]}});

	j["inputs"] = json::object();
	for (auto& [name, code] : inputs)
		j["inputs"][name] = code;

	j["profiles"] = json::object();
	for (auto& [profName, monMap] : profiles) {
		j["profiles"][profName] = json::object();
		for (auto& [monId, inputName] : monMap)
			j["profiles"][profName][std::to_string(monId)] = inputName;
	}

	std::ofstream out(configPath);
	if (!out.is_open()) {
		std::cerr << "Error: Cannot write to " << configPath << std::endl;
		std::cerr << "Config JSON (copy manually):" << std::endl;
		std::cerr << j.dump(2) << std::endl;
		return;
	}
	out << j.dump(2) << std::endl;
	std::cout << "Config written to: " << configPath << std::endl;
}

int setupWizard(std::vector<std::string> args) {
	std::cout << std::endl;
	std::cout << "==============================" << std::endl;
	std::cout << " Monitor Setup Wizard" << std::endl;
	std::cout << "==============================" << std::endl;
	std::cout << std::endl;

	if (physicalMonitors.empty()) {
		std::cerr << "Error: No monitors detected. Make sure monitors are connected and DDC/CI is enabled." << std::endl;
		return 1;
	}

	size_t totalMonitors = physicalMonitors.size();
	std::cout << "Found " << totalMonitors << " monitor(s)." << std::endl << std::endl;

	// Phase A: identify monitors by blinking each one
	std::cout << "===================================================" << std::endl;
	std::cout << "Phase 1: Display Identification" << std::endl;
	std::cout << "===================================================" << std::endl;
	std::cout << std::endl;
	std::cout << "Available options:" << std::endl;
	std::cout << "  * Enter a name (e.g. 'Left', 'Right') if you see flashing" << std::endl;
	std::cout << "  * Type 'skip' if you don't see any flash" << std::endl;
	std::cout << "  * Type 'manual' to directly enter display names without blinking" << std::endl;
	std::cout << std::endl;
	std::cout << "How would you like to identify monitors? (auto/manual) [auto]: ";
	std::string idMode;
	std::getline(std::cin, idMode);
	if (idMode.empty()) idMode = "auto";
	std::cout << std::endl;

	std::vector<size_t> activeMonitors;
	std::vector<std::string> monitorNames(totalMonitors);

	if (idMode == "manual" || idMode == "m") {
		std::cout << "Manual mode: Configure each display directly." << std::endl;
		std::cout << std::endl;
		for (size_t i = 0; i < totalMonitors; i++)
			std::cout << "  Display " << i << ": " << toUtf8(physicalMonitors[i].szPhysicalMonitorDescription) << std::endl;
		std::cout << std::endl;
		for (size_t i = 0; i < totalMonitors; i++) {
			std::cout << "Configure display " << i << "? Enter name or 'skip': ";
			std::string nameInput;
			std::getline(std::cin, nameInput);
			if (nameInput == "skip" || nameInput == "s") {
				std::cout << "  Skipping Display " << i << std::endl;
			} else {
				if (nameInput.empty()) nameInput = "Display" + std::to_string(i);
				monitorNames[i] = nameInput;
				activeMonitors.push_back(i);
				std::cout << "  OK: Display " << i << ": " << nameInput << std::endl;
			}
			std::cout << std::endl;
		}
	} else {
		// Auto mode with blinking
		for (size_t i = 0; i < totalMonitors; i++) {
			std::cout << "-------------------------------------" << std::endl;
			std::cout << "Testing Display " << i << ": " << toUtf8(physicalMonitors[i].szPhysicalMonitorDescription) << std::endl;
			std::cout << "-------------------------------------" << std::endl;
			std::cout << "Watch your monitors carefully..." << std::endl;
			std::cout << std::endl;
			blinkMonitor(physicalMonitors[i].hPhysicalMonitor, i);
			std::cout << std::endl;
			std::cout << "Which monitor flashed? (Enter name, or 'skip'): ";
			std::string nameInput;
			std::getline(std::cin, nameInput);
			if (nameInput == "skip" || nameInput == "s") {
				std::cout << "  Skipping Display " << i << " (will not be configured)" << std::endl;
			} else {
				if (nameInput.empty()) nameInput = "Display" + std::to_string(i);
				monitorNames[i] = nameInput;
				activeMonitors.push_back(i);
				std::cout << "  OK: Display " << i << ": " << nameInput << std::endl;
			}
			std::cout << std::endl;
		}
	}

	if (activeMonitors.empty()) {
		std::cerr << "Error: No displays confirmed. Setup cancelled." << std::endl;
		return 1;
	}

	std::cout << "Proceeding with " << activeMonitors.size() << " confirmed display(s)." << std::endl;
	std::cout << std::endl;

	// Phase B: interactive probe — for each confirmed monitor, let user try VCP codes
	std::cout << "===================================================" << std::endl;
	std::cout << "Phase 2: Input Source Detection" << std::endl;
	std::cout << "===================================================" << std::endl;
	std::cout << std::endl;
	std::cout << "We need to identify which VCP code corresponds to THIS Windows system." << std::endl;
	std::cout << "The detected value is usually correct - just press Enter to use it." << std::endl;
	std::cout << std::endl;
	std::cout << "  WARNING: Testing wrong codes will temporarily switch your monitor away!" << std::endl;
	std::cout << "  Only test if you're sure the detected value is wrong." << std::endl;
	std::cout << std::endl;

	static const std::vector<int> defaultCandidates = {15, 16, 17, 18, 19, 3, 4, 27};
	std::vector<int> confirmedCodes(totalMonitors, 0);

	for (size_t i : activeMonitors) {
		DWORD currentVal = 0;
		GetVCPFeatureAndVCPFeatureReply(physicalMonitors[i].hPhysicalMonitor, 0x60, NULL, &currentVal, NULL);

		std::string caps = getCapabilitiesString(i);
		std::vector<int> candidates;
		if (!caps.empty()) candidates = parseInputCodesFromCapabilities(caps);
		if (candidates.empty()) candidates = defaultCandidates;

		if (currentVal != 0) {
			bool found = false;
			for (int c : candidates) if (c == (int)currentVal) { found = true; break; }
			if (!found) candidates.push_back((int)currentVal);
		}

		std::cout << "---------------------------------------------------" << std::endl;
		std::cout << "Display: " << monitorNames[i] << " (ID: " << i << ")" << std::endl;
		std::cout << "---------------------------------------------------" << std::endl;
		std::cout << std::endl;
		std::cout << "Detected current input: " << currentVal << " (" << knownInputName((int)currentVal) << ")" << std::endl;
		std::cout << std::endl;
		std::cout << "Common VCP codes for reference:" << std::endl;
		for (int c : candidates) {
			if (c == (int)currentVal)
				std::printf("  %2d - %s  <- DETECTED\n", c, knownInputName(c).c_str());
			else
				std::printf("  %2d - %s\n", c, knownInputName(c).c_str());
		}
		std::cout << std::endl;
		std::cout << "Options:" << std::endl;
		std::cout << "  * Press ENTER to use detected value " << currentVal << " (recommended)" << std::endl;
		std::cout << "  * Enter a code number to test it (screen may go black temporarily!)" << std::endl;
		std::cout << std::endl;

		while (true) {
			std::cout << "Your choice [Enter=" << currentVal << "]: ";
			std::string line;
			std::getline(std::cin, line);

			if (line.empty()) {
				confirmedCodes[i] = (int)currentVal;
				std::cout << "  OK: Using detected value: " << currentVal
				          << " (" << knownInputName((int)currentVal) << ")" << std::endl;
				break;
			}

			int testCode;
			try { testCode = std::stoi(line); }
			catch (...) {
				std::cout << "  Invalid input. Enter a number or press Enter." << std::endl;
				continue;
			}

			std::cout << std::endl;
			std::cout << "=== WARNING ===" << std::endl;
			std::cout << "  Testing code " << testCode << " (" << knownInputName(testCode) << ")" << std::endl;
			std::cout << "  Your screen may go BLACK or switch to another system!" << std::endl;
			std::cout << "  It will AUTO-RESTORE in 3 seconds - DO NOT TOUCH ANYTHING!" << std::endl;
			std::cout << std::endl;
			std::cout << "Continue with this test? (y/n): ";
			std::string confirmTest;
			std::getline(std::cin, confirmTest);

			if (confirmTest != "y" && confirmTest != "Y") {
				std::cout << "  Test cancelled." << std::endl;
				continue;
			}

			std::cout << std::endl;
			std::cout << "  Switching to code " << testCode << " in:" << std::endl;
			std::cout << "  3..." << std::flush; Sleep(1000);
			std::cout << " 2..." << std::flush; Sleep(1000);
			std::cout << " 1..." << std::endl;   Sleep(1000);

			SetVCPFeature(physicalMonitors[i].hPhysicalMonitor, 0x60, testCode);

			std::cout << "  [Testing for 3 seconds";
			for (int s = 0; s < 3; s++) { Sleep(1000); std::cout << "." << std::flush; }
			std::cout << "]" << std::endl;

			// Auto-restore
			SetVCPFeature(physicalMonitors[i].hPhysicalMonitor, 0x60, currentVal);
			Sleep(1000);

			std::cout << std::endl;
			std::cout << "  OK: Restored to original input" << std::endl;
			std::cout << std::endl;
			std::cout << "What happened during the test?" << std::endl;
			std::cout << "  1) Screen stayed NORMAL (no change) -> code " << testCode << " is CORRECT" << std::endl;
			std::cout << "  2) Screen went BLACK or switched away -> code " << testCode << " is WRONG" << std::endl;
			std::cout << std::endl;
			std::cout << "Did the screen stay normal? (y/n): ";
			std::string yn;
			std::getline(std::cin, yn);

			if (yn == "y" || yn == "Y") {
				confirmedCodes[i] = testCode;
				std::cout << "  Confirmed: code " << testCode << " (" << knownInputName(testCode) << ")" << std::endl;
				break;
			} else {
				std::cout << "  Code " << testCode << " is incorrect. Try another or press Enter for " << currentVal << "." << std::endl;
				std::cout << std::endl;
			}
		}
		std::cout << std::endl;
	}

	// Phase C: ask profile name for this system
	std::cout << "-------------------------------------" << std::endl;
	std::cout << "Profile name for this system (e.g. 'windows', 'mac', 'linux'): ";
	std::string profileName;
	std::getline(std::cin, profileName);
	if (profileName.empty()) {
		std::cerr << "Profile name cannot be empty. Setup cancelled." << std::endl;
		return 1;
	}
	std::cout << std::endl;

	// Phase D: merge with existing config
	std::string configPath = getConfigPath();
	Config existing;
	{
		std::ifstream f(configPath);
		if (f.is_open()) {
			existing = loadConfig();
			std::cout << "Existing config found. Will merge." << std::endl;
		}
	}

	std::unordered_map<std::string, int> inputsMap = existing.inputs;

	std::unordered_map<int, std::string> newProfile;
	int monIdx = 0;
	for (size_t i : activeMonitors) {
		int code = confirmedCodes[i];
		if (code == 0) { monIdx++; continue; }
		std::string inputName;
		for (auto& [name, c] : inputsMap)
			if (c == code) { inputName = name; break; }
		if (inputName.empty()) {
			inputName = autoInputKey(code);
			while (inputsMap.count(inputName) && inputsMap[inputName] != code)
				inputName += "_";
			inputsMap[inputName] = code;
		}
		newProfile[monIdx] = inputName;
		monIdx++;
	}

	std::unordered_map<std::string, std::unordered_map<int, std::string>> profiles = existing.profiles;
	profiles[profileName] = newProfile;

	std::vector<std::pair<std::string, int>> inputVec(inputsMap.begin(), inputsMap.end());

	// Phase E: human-readable preview and confirm
	size_t monitorCount = activeMonitors.size();

	std::vector<std::string> activeNames;
	for (size_t i : activeMonitors) activeNames.push_back(monitorNames[i]);

	std::cout << std::endl;
	std::cout << "===================================================" << std::endl;
	std::cout << "Configuration Preview" << std::endl;
	std::cout << "===================================================" << std::endl;
	std::cout << std::endl;
	std::cout << "VCP Code: 0x60 (Input Source)" << std::endl;
	std::cout << std::endl;
	std::cout << "Monitors:" << std::endl;
	monIdx = 0;
	for (size_t i : activeMonitors) {
		std::printf("  [%d] %s (Display ID: %zu)\n", monIdx, monitorNames[i].c_str(), i);
		monIdx++;
	}
	std::cout << std::endl;
	std::cout << "Input Codes:" << std::endl;
	for (auto& [name, code] : inputsMap)
		std::printf("  %-12s -> VCP value %d (%s)\n", name.c_str(), code, knownInputName(code).c_str());
	std::cout << std::endl;
	std::cout << "Profiles:" << std::endl;
	for (auto& [profName, monMap] : profiles) {
		if (profName != profileName)
			std::cout << "  * " << profName << ": (kept from existing config)" << std::endl;
	}
	std::cout << "  * " << profileName << ": (NEW)" << std::endl;
	monIdx = 0;
	for (size_t i : activeMonitors) {
		auto it = newProfile.find(monIdx);
		std::string inp = (it != newProfile.end()) ? it->second : "(none)";
		std::printf("      [%d] %s -> %s\n", monIdx, monitorNames[i].c_str(), inp.c_str());
		monIdx++;
	}
	std::cout << std::endl;
	std::cout << "===================================================" << std::endl;
	std::cout << std::endl;

	std::cout << "Save this configuration to config/monitors.json? (y/n): ";
	std::string confirm;
	std::getline(std::cin, confirm);
	if (confirm != "y" && confirm != "Y") {
		std::cout << "Setup cancelled." << std::endl;
		return 1;
	}

	writeConfig(configPath, inputVec, monitorCount, activeNames, profiles);

	std::cout << std::endl;
	std::cout << "OK: Configuration saved to: " << configPath << std::endl;
	std::cout << std::endl;
	std::cout << "-------------------------------------" << std::endl;
	std::cout << "Setup complete!" << std::endl;
	std::cout << "-------------------------------------" << std::endl;
	if (profiles.size() < 2)
		std::cout << "Note: Run setup on the other system to add its profile." << std::endl;
	std::cout << "To test the configuration, run:" << std::endl;
	std::cout << "  switch.bat " << profileName << std::endl;
	std::cout << std::endl;

	return 0;
}

// ─────────────────────────────────────────────────────────────────────────────

std::unordered_map<std::string, std::function<int(std::vector<std::string>)>> commands
{
	{ "help",       printUsage },
	{ "detect",     detect },
	{ "capabilities", capabilities },
	{ "getvcp",     getVcp },
	{ "setvcp",     setVcp },
	{ "switch",     switchProfile },
	{ "setup",      setupWizard },
	{ "autodetect", setupWizard },
};

int main(int argc, char *argv[], char *envp[])
{
	std::vector<std::string> args;

	if (argc < 2)
		return printUsage(args);

	for (int i = 1; i < argc; i++) {
		std::string arg(argv[i]);
		args.emplace_back(arg);
	}

	auto command = commands.find(args[0]);
	if (command == commands.end()) {
		std::cerr << "Unknown command: " << args[0] << std::endl << std::endl;
		return printUsage(args);
	}
	args.erase(args.begin());

	EnumDisplayMonitors(NULL, NULL, &monitorEnumProcCallback, 0);

	auto success = command->second(args);

	DestroyPhysicalMonitors(physicalMonitors.size(), physicalMonitors.data());

	return success;
}
