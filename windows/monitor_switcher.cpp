#include <atlstr.h>
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

std::string toUtf8(wchar_t *buffer)
{
	CW2A utf8(buffer, CP_UTF8);
	const char* data = utf8.m_psz;
	return std::string{ data };
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
	std::unordered_map<std::string, std::string> profiles = {{"windows", "dp1"}, {"mac", "hdmi2"}};
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
			for (auto& [key, val] : j["profiles"].items())
				if (val.is_string()) config.profiles[key] = val.get<std::string>();
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

	std::string inputName = config.profiles[profileName];
	if (config.inputs.find(inputName) == config.inputs.end()) {
		std::cerr << "Unknown input: " << inputName << std::endl;
		return 1;
	}

	int inputValue = config.inputs[inputName];

	std::cout << "Switching all monitors to profile '" << profileName << "' (input: " << inputName
	          << ", value: " << inputValue << ")" << std::endl;
	std::cout << std::endl;

	bool anySuccess = false;
	bool anyFailure = false;

	for (size_t i = 0; i < physicalMonitors.size(); i++) {
		std::cout << "Display " << i << ": ";

		bool success = false;
		for (int retry = 0; retry < 3 && !success; retry++) {
			if (retry > 0) {
				Sleep(500);
				std::cout << "Retry " << retry << "... ";
			}
			success = SetVCPFeature(physicalMonitors[i].hPhysicalMonitor, config.vcpCode, inputValue);
		}

		if (success) {
			std::cout << "OK" << std::endl;
			anySuccess = true;
		} else {
			std::cout << "FAILED" << std::endl;
			anyFailure = true;
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

void blinkMonitor(HANDLE hMonitor, int times = 3) {
	DWORD originalBrightness = 50;
	GetVCPFeatureAndVCPFeatureReply(hMonitor, 0x10, NULL, &originalBrightness, NULL);
	for (int i = 0; i < times; i++) {
		SetVCPFeature(hMonitor, 0x10, 5);
		Sleep(300);
		SetVCPFeature(hMonitor, 0x10, originalBrightness);
		Sleep(300);
	}
}

void writeConfig(const std::string& configPath,
                 const std::vector<std::pair<std::string, int>>& inputs,
                 const std::string& windowsInput,
                 const std::string& macInput) {
	json j;
	j["vcp_code"] = "0x60";
	j["inputs"] = json::object();
	for (auto& [name, code] : inputs)
		j["inputs"][name] = code;
	j["profiles"]["windows"] = windowsInput;
	j["profiles"]["mac"] = macInput;

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

	size_t monitorCount = physicalMonitors.size();
	std::cout << "Found " << monitorCount << " monitor(s)." << std::endl << std::endl;

	// Phase A: identify monitors by blinking each one
	std::vector<std::string> monitorNames(monitorCount);
	for (size_t i = 0; i < monitorCount; i++) {
		std::cout << "--- Display " << i << ": " << toUtf8(physicalMonitors[i].szPhysicalMonitorDescription) << " ---" << std::endl;
		std::cout << "Watch for a brightness flash on one of your screens..." << std::endl;
		blinkMonitor(physicalMonitors[i].hPhysicalMonitor);
		std::cout << "Enter a friendly name for the screen that just flashed (e.g. Left, Right): ";
		std::getline(std::cin, monitorNames[i]);
		if (monitorNames[i].empty()) monitorNames[i] = "Display" + std::to_string(i);
		std::cout << std::endl;
	}

	// Phase B: discover input codes for each monitor
	// Collect unique codes across all monitors
	std::vector<int> allCodes;
	std::vector<DWORD> currentInputs(monitorCount, 0);
	static const std::vector<int> fallbackCodes = {15, 16, 17, 18, 19};

	for (size_t i = 0; i < monitorCount; i++) {
		// Read current input code
		GetVCPFeatureAndVCPFeatureReply(physicalMonitors[i].hPhysicalMonitor, 0x60, NULL, &currentInputs[i], NULL);

		// Try capabilities string first
		std::cout << "Querying capabilities for Display " << i << " (" << monitorNames[i] << ")..." << std::endl;
		std::string caps = getCapabilitiesString(i);
		std::vector<int> codes;
		if (!caps.empty()) {
			codes = parseInputCodesFromCapabilities(caps);
		}
		if (codes.empty()) {
			std::cout << "  (Could not parse capabilities, using standard DDC input list)" << std::endl;
			codes = fallbackCodes;
		}

		// Make sure current input is included even if not in caps
		if (currentInputs[i] != 0) {
			bool found = false;
			for (int c : codes) if (c == (int)currentInputs[i]) { found = true; break; }
			if (!found) codes.push_back((int)currentInputs[i]);
		}

		std::cout << "  Input codes:" << std::endl;
		for (int code : codes) {
			std::string marker = (currentInputs[i] == (DWORD)code) ? "  [CURRENT - this system]" : "";
			std::printf("    %2d (0x%02X) — %s%s\n", code, code, knownInputName(code).c_str(), marker.c_str());
			// Add to allCodes (deduplicated)
			bool exists = false;
			for (int c : allCodes) if (c == code) { exists = true; break; }
			if (!exists) allCodes.push_back(code);
		}
		std::cout << std::endl;
	}

	// Phase C: name each unique input code
	std::cout << "--- Name the inputs ---" << std::endl;
	std::cout << "Give each input a short key name (e.g. 'dp1', 'hdmi2')." << std::endl;
	std::cout << "Press Enter to skip codes you don't use." << std::endl << std::endl;

	std::vector<std::pair<std::string, int>> namedInputs;
	for (int code : allCodes) {
		bool isCurrent = false;
		for (DWORD cur : currentInputs) if (cur == (DWORD)code) { isCurrent = true; break; }
		std::printf("  Code %2d (0x%02X) — %s%s" , code, code, knownInputName(code).c_str(),
		            isCurrent ? " [current system]" : "");
		std::cout << std::endl << "  Key name (or Enter to skip): ";
		std::string keyName;
		std::getline(std::cin, keyName);
		if (!keyName.empty()) {
			namedInputs.push_back({keyName, code});
		}
	}

	if (namedInputs.empty()) {
		std::cerr << "No inputs named. Setup cancelled." << std::endl;
		return 1;
	}

	std::cout << std::endl << "Named inputs:" << std::endl;
	for (auto& [name, code] : namedInputs)
		std::printf("  %-12s = %d\n", name.c_str(), code);
	std::cout << std::endl;

	// Phase D: assign profiles
	auto validateInput = [&](const std::string& label) -> std::string {
		while (true) {
			std::cout << label;
			std::string val;
			std::getline(std::cin, val);
			for (auto& [name, code] : namedInputs)
				if (name == val) return val;
			std::cout << "  '" << val << "' not in your list. Available: ";
			for (auto& [name, code] : namedInputs) std::cout << name << " ";
			std::cout << std::endl;
		}
	};

	std::string windowsInput = validateInput("Which input is for Windows? Enter key name: ");
	std::string macInput     = validateInput("Which input is for Mac?     Enter key name: ");

	// Phase E: preview and write
	std::cout << std::endl << "Will write:" << std::endl;
	json preview;
	preview["vcp_code"] = "0x60";
	preview["inputs"] = json::object();
	for (auto& [name, code] : namedInputs) preview["inputs"][name] = code;
	preview["profiles"]["windows"] = windowsInput;
	preview["profiles"]["mac"] = macInput;
	std::cout << preview.dump(2) << std::endl << std::endl;

	std::cout << "Write to config/monitors.json? (y/n): ";
	std::string confirm;
	std::getline(std::cin, confirm);
	if (confirm != "y" && confirm != "Y") {
		std::cout << "Setup cancelled." << std::endl;
		return 1;
	}

	writeConfig(getConfigPath(), namedInputs, windowsInput, macInput);

	std::cout << std::endl;
	std::cout << "Setup complete! Test with:" << std::endl;
	std::cout << "  switch.bat windows" << std::endl;
	std::cout << "  switch.bat mac" << std::endl;

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
