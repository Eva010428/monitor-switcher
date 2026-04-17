#!/bin/bash
# Monitor Switcher for macOS
# Wrapper script for ddcctl / m1ddc
#
# This script reads config/monitors.json and calls the DDC tool to switch monitor inputs.
# Requires: m1ddc (Apple Silicon) or ddcctl (Intel Mac)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/monitors.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if jq is installed for JSON parsing
if ! command -v jq &> /dev/null; then
    USE_JQ=false
else
    USE_JQ=true
fi

# Check which DDC tool is available
DDC_TOOL=""
if command -v m1ddc &> /dev/null; then
    DDC_TOOL="m1ddc"
elif command -v ddcctl &> /dev/null; then
    DDC_TOOL="ddcctl"
else
    echo -e "${RED}Error: No DDC control tool found${NC}"
    echo "Please install one of the following:"
    echo "  brew install m1ddc     # For Apple Silicon (recommended)"
    echo "  brew install ddcctl    # For Intel Mac"
    exit 1
fi

echo -e "${GREEN}Using DDC tool: ${DDC_TOOL}${NC}"

function print_usage() {
    echo "Monitor Switcher for macOS"
    echo "==========================="
    echo ""
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  switch <profile>    Switch monitors to profile (windows|mac)"
    echo "  setup               Run interactive setup wizard"
    echo "  detect              Detect monitors"
    echo "  help                Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 setup            Auto-detect inputs and write config"
    echo "  $0 switch mac       Switch to Mac"
    echo "  $0 switch windows   Switch to Windows"
}

function load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config not found: $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Run './switch.sh setup' to auto-configure.${NC}" >&2
        exit 1
    fi

    local profile=$1

    if [ "$USE_JQ" = true ]; then
        local input_name
        input_name=$(jq -r ".profiles[\"$profile\"]" "$CONFIG_FILE")
        if [ "$input_name" = "null" ] || [ -z "$input_name" ]; then
            echo -e "${RED}Error: Profile '$profile' not found in config.${NC}" >&2
            exit 1
        fi
        local input_value
        input_value=$(jq -r ".inputs[\"$input_name\"]" "$CONFIG_FILE")
        if [ "$input_value" = "null" ] || [ -z "$input_value" ]; then
            echo -e "${RED}Error: Input '$input_name' not found in config.${NC}" >&2
            exit 1
        fi
        echo "$input_value"
    else
        # grep/sed fallback — works with the fixed format written by write_config()
        local input_name
        input_name=$(awk '/"profiles"/,/\}/' "$CONFIG_FILE" \
                     | grep "\"$profile\"" \
                     | sed 's/.*:[ ]*"\([^"]*\)".*/\1/')
        if [ -z "$input_name" ]; then
            echo -e "${RED}Error: Profile '$profile' not found in config.${NC}" >&2
            exit 1
        fi
        local input_value
        input_value=$(awk '/"inputs"/,/\}/' "$CONFIG_FILE" \
                      | grep "\"$input_name\"" \
                      | grep -oE '[0-9]+')
        if [ -z "$input_value" ]; then
            echo -e "${RED}Error: Input '$input_name' not found in config.${NC}" >&2
            exit 1
        fi
        echo "$input_value"
    fi
}

function detect_monitors() {
    echo "Detecting monitors..."
    echo ""

    if [ "$DDC_TOOL" = "m1ddc" ]; then
        m1ddc display list
        echo ""
        echo "Testing DDC/CI support..."
        for d in 1 2 3 4; do
            local result
            result=$(m1ddc display "$d" get luminance 2>&1 || true)
            if echo "$result" | grep -qi "failure\|not found"; then
                echo -e "Display $d: ${YELLOW}Not supported (HDMI port or not connected)${NC}"
            else
                echo -e "Display $d: ${GREEN}Supported${NC}"
            fi
        done
    else
        ddcctl -d 1 2>/dev/null || echo "Display 1: Not found or not supported"
        ddcctl -d 2 2>/dev/null || echo "Display 2: Not found or not supported"
    fi

    echo ""
    echo "Tip: Run './switch.sh setup' to auto-detect input codes"
}

function switch_profile() {
    local profile=$1

    if [ -z "$profile" ]; then
        echo -e "${RED}Error: Profile name required${NC}"
        print_usage
        exit 1
    fi

    local input_value
    input_value=$(load_config "$profile")

    if [ -z "$input_value" ]; then
        echo -e "${RED}Error: Could not determine input value for profile '$profile'${NC}"
        exit 1
    fi

    echo "Switching monitors to profile '$profile' (input value: $input_value)"
    echo "Using tool: $DDC_TOOL"
    echo ""

    local success=0
    local failure=0

    for d in 1 2 3 4; do
        # Check if this display responds at all
        local probe_result
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            probe_result=$(m1ddc display "$d" get luminance 2>&1 || true)
        else
            probe_result=$(ddcctl -d "$d" 2>&1 || true)
        fi
        if echo "$probe_result" | grep -qi "failure\|not found\|no display"; then
            continue  # skip unresponsive displays
        fi

        echo -n "Display $d: "
        local switch_result
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            switch_result=$(m1ddc display "$d" set input "$input_value" 2>&1 || true)
        else
            switch_result=$(ddcctl -d "$d" -i "$input_value" 2>&1 || true)
        fi

        if echo "$switch_result" | grep -qi "failure\|error"; then
            echo -e "${RED}FAILED${NC}"
            ((failure++)) || true
        else
            echo -e "${GREEN}OK${NC}"
            ((success++)) || true
        fi
    done

    echo ""
    if [ "${success:-0}" -gt 0 ] && [ "${failure:-0}" -eq 0 ]; then
        echo -e "${GREEN}Monitors switched successfully!${NC}"
        exit 0
    elif [ "${success:-0}" -gt 0 ]; then
        echo -e "${YELLOW}Some monitors failed to switch.${NC}"
        exit 2
    else
        echo -e "${RED}Failed to switch any monitor.${NC}"
        exit 1
    fi
}

# ─── Setup Wizard helpers ────────────────────────────────────────────────────

function known_input_name() {
    case "$1" in
        3)  echo "DVI 1" ;;
        4)  echo "DVI 2" ;;
        15) echo "DisplayPort 1" ;;
        16) echo "DisplayPort 2" ;;
        17) echo "HDMI 1" ;;
        18) echo "HDMI 2" ;;
        19) echo "HDMI 3" ;;
        27) echo "USB-C / DP" ;;
        *)  echo "Unknown" ;;
    esac
}

function blink_monitor() {
    local d=$1
    local original_lum="50"

    if [ "$DDC_TOOL" = "m1ddc" ]; then
        original_lum=$(m1ddc display "$d" get luminance 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "50")
        for i in 1 2 3; do
            m1ddc display "$d" set luminance 2 &>/dev/null || true
            sleep 0.3
            m1ddc display "$d" set luminance "$original_lum" &>/dev/null || true
            sleep 0.3
        done
    else
        original_lum=$(ddcctl -d "$d" 2>/dev/null | grep -i "luminance\|brightness" | grep -oE '[0-9]+' | head -1 || echo "50")
        for i in 1 2 3; do
            ddcctl -d "$d" -b 2 &>/dev/null || true
            sleep 0.3
            ddcctl -d "$d" -b "$original_lum" &>/dev/null || true
            sleep 0.3
        done
    fi
}

function get_current_input() {
    local d=$1
    local code=""
    if [ "$DDC_TOOL" = "m1ddc" ]; then
        code=$(m1ddc display "$d" get input 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)
    else
        code=$(ddcctl -d "$d" 2>/dev/null | grep -i "input source" | grep -oE '[0-9]+' | head -1 || true)
    fi
    echo "${code:-0}"
}

function probe_input_codes() {
    local d=$1
    local probe_list=(15 16 17 18 19 3 4 27)
    local -a working=()

    local current
    current=$(get_current_input "$d")

    echo "  Probing standard DDC input codes for Display $d..." >&2
    echo "  (Monitor may flicker briefly — this is normal)" >&2

    for code in "${probe_list[@]}"; do
        printf "  Testing code %2d (%s)... " "$code" "$(known_input_name "$code")" >&2
        local result
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            result=$(m1ddc display "$d" set input "$code" 2>&1 || true)
        else
            result=$(ddcctl -d "$d" -i "$code" 2>&1 || true)
        fi

        if echo "$result" | grep -qi "failure\|error\|not supported"; then
            echo "rejected" >&2
        else
            echo "accepted" >&2
            working+=("$code")
        fi
        sleep 0.5
    done

    # Restore original input
    if [ -n "$current" ] && [ "$current" != "0" ]; then
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            m1ddc display "$d" set input "$current" &>/dev/null || true
        else
            ddcctl -d "$d" -i "$current" &>/dev/null || true
        fi
    fi

    printf '%s\n' "${working[@]}"
}

function write_config() {
    # Args: windows_input windows_code mac_input mac_code [extra_name extra_code ...]
    local windows_input=$1
    local windows_code=$2
    local mac_input=$3
    local mac_code=$4
    shift 4
    local extra_pairs=("$@")

    {
        printf '{\n'
        printf '  "vcp_code": "0x60",\n'
        printf '  "inputs": {\n'
        printf '    "%s": %d' "$windows_input" "$windows_code"
        if [ "$mac_input" != "$windows_input" ]; then
            printf ',\n    "%s": %d' "$mac_input" "$mac_code"
        fi
        local i=0
        while [ "$i" -lt "${#extra_pairs[@]}" ]; do
            printf ',\n    "%s": %d' "${extra_pairs[$i]}" "${extra_pairs[$((i+1))]}"
            i=$((i+2))
        done
        printf '\n  },\n'
        printf '  "profiles": {\n'
        printf '    "windows": "%s",\n' "$windows_input"
        printf '    "mac": "%s"\n' "$mac_input"
        printf '  }\n'
        printf '}\n'
    } > "$CONFIG_FILE"

    echo -e "${GREEN}Config written to: $CONFIG_FILE${NC}"
}

function setup_wizard() {
    echo ""
    echo "=============================="
    echo " Monitor Setup Wizard"
    echo "=============================="
    echo ""

    # Find DDC/CI-capable displays
    local display_list=()
    for d in 1 2 3 4; do
        local result
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            result=$(m1ddc display "$d" get luminance 2>&1 || true)
        else
            result=$(ddcctl -d "$d" 2>&1 || true)
        fi
        if ! echo "$result" | grep -qi "failure\|not found\|no display"; then
            display_list+=("$d")
        fi
    done

    if [ "${#display_list[@]}" -eq 0 ]; then
        echo -e "${RED}Error: No DDC/CI-capable displays found.${NC}"
        echo "Make sure:"
        echo "  - Monitors are connected via Thunderbolt/USB-C (not HDMI on Apple Silicon)"
        echo "  - DDC/CI is enabled in each monitor's OSD menu"
        exit 1
    fi

    echo "Found ${#display_list[@]} DDC/CI-capable display(s): ${display_list[*]}"
    echo ""

    # Phase A: identify each display by blinking
    declare -A monitor_names
    for d in "${display_list[@]}"; do
        echo "--- Display $d ---"
        echo "Watch for a brightness flash on one of your screens..."
        blink_monitor "$d"
        read -r -p "Which physical monitor just flashed? Enter a name (e.g. Left, Right): " monitor_names[$d]
        if [ -z "${monitor_names[$d]}" ]; then monitor_names[$d]="Display$d"; fi
        echo ""
    done

    # Phase B: read current input codes
    declare -A current_codes
    for d in "${display_list[@]}"; do
        current_codes[$d]=$(get_current_input "$d")
        if [ -n "${current_codes[$d]}" ] && [ "${current_codes[$d]}" != "0" ]; then
            echo "Display $d (${monitor_names[$d]}) current input: ${current_codes[$d]} ($(known_input_name "${current_codes[$d]}"))"
        fi
    done
    echo ""

    # Phase B continued: probe input codes using the first responsive display
    local first_display="${display_list[0]}"
    echo "Probing available input codes on Display $first_display..."
    echo ""
    mapfile -t available_codes < <(probe_input_codes "$first_display")

    if [ "${#available_codes[@]}" -eq 0 ]; then
        echo -e "${YELLOW}Warning: Could not auto-detect input codes. Using standard DDC list.${NC}"
        available_codes=(15 16 17 18)
    fi

    # Ensure current input code is in the list
    for d in "${display_list[@]}"; do
        local cur="${current_codes[$d]}"
        if [ -n "$cur" ] && [ "$cur" != "0" ]; then
            local found=false
            for c in "${available_codes[@]}"; do
                if [ "$c" = "$cur" ]; then found=true; break; fi
            done
            if [ "$found" = false ]; then
                available_codes+=("$cur")
            fi
        fi
    done

    echo ""
    echo "Available input codes:"
    for code in "${available_codes[@]}"; do
        local marker=""
        for d in "${display_list[@]}"; do
            if [ "${current_codes[$d]}" = "$code" ]; then marker="  [CURRENT - this system]"; break; fi
        done
        printf "  %2d (0x%02X) — %s%s\n" "$code" "$code" "$(known_input_name "$code")" "$marker"
    done
    echo ""

    # Phase C: name each input code
    echo "--- Name the inputs ---"
    echo "Give each input a short key name (e.g. 'dp1', 'hdmi2')."
    echo "Press Enter to skip codes you don't use."
    echo ""

    declare -A input_map  # key_name -> code
    for code in "${available_codes[@]}"; do
        local is_current=false
        for d in "${display_list[@]}"; do
            if [ "${current_codes[$d]}" = "$code" ]; then is_current=true; break; fi
        done
        local label=""
        if [ "$is_current" = true ]; then label=" [current system]"; fi
        printf "  Code %2d (0x%02X) — %s%s\n" "$code" "$code" "$(known_input_name "$code")" "$label"
        read -r -p "  Key name (or Enter to skip): " key_name
        if [ -n "$key_name" ]; then
            input_map["$key_name"]=$code
        fi
    done

    if [ "${#input_map[@]}" -eq 0 ]; then
        echo "No inputs named. Setup cancelled."
        exit 1
    fi

    echo ""
    echo "Named inputs:"
    for key in "${!input_map[@]}"; do
        printf "  %-12s = %d\n" "$key" "${input_map[$key]}"
    done
    echo ""

    # Phase D: assign profiles
    local windows_input mac_input

    while true; do
        read -r -p "Which input name is for Windows? " windows_input
        if [ -n "${input_map[$windows_input]+_}" ]; then break; fi
        echo "  '$windows_input' not in your list. Available: ${!input_map[*]}"
    done

    while true; do
        read -r -p "Which input name is for Mac? " mac_input
        if [ -n "${input_map[$mac_input]+_}" ]; then break; fi
        echo "  '$mac_input' not in your list. Available: ${!input_map[*]}"
    done

    # Phase E: preview and confirm
    echo ""
    echo "Will write the following config:"
    echo "  vcp_code: 0x60"
    echo "  inputs:"
    for key in "${!input_map[@]}"; do
        printf "    %-12s = %d\n" "$key" "${input_map[$key]}"
    done
    echo "  profiles:"
    echo "    windows: $windows_input"
    echo "    mac: $mac_input"
    echo ""

    read -r -p "Write to $CONFIG_FILE? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Setup cancelled."
        exit 1
    fi

    # Build write_config argument list
    local write_args=("$windows_input" "${input_map[$windows_input]}" "$mac_input" "${input_map[$mac_input]}")
    for key in "${!input_map[@]}"; do
        if [ "$key" != "$windows_input" ] && [ "$key" != "$mac_input" ]; then
            write_args+=("$key" "${input_map[$key]}")
        fi
    done

    write_config "${write_args[@]}"

    echo ""
    echo "Setup complete! Test with:"
    echo "  ./switch.sh windows"
    echo "  ./switch.sh mac"
}

# ─────────────────────────────────────────────────────────────────────────────
# Main
if [ $# -eq 0 ]; then
    print_usage
    exit 1
fi

case "$1" in
    help|--help|-h)
        print_usage
        ;;
    detect)
        detect_monitors
        ;;
    switch)
        shift
        switch_profile "$@"
        ;;
    setup|autodetect)
        setup_wizard
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac
