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

    # Get all connected displays
    local all_connected=()
    _get_connected_displays all_connected

    if [ "$DDC_TOOL" = "m1ddc" ]; then
        echo "=== M1DDC Display List ==="
        m1ddc display list
        echo ""
    fi

    echo "=== Testing DDC/CI Support ==="
    echo "Connected display IDs: ${all_connected[*]}"
    echo ""
    
    local found_any=false
    for d in "${all_connected[@]}"; do
        echo -n "Display $d: "
        if [ "$DDC_TOOL" = "m1ddc" ]; then
            local result
            result=$(m1ddc display "$d" get luminance 2>&1 || true)
            if echo "$result" | grep -qi "failure\|not found\|error\|disabled"; then
                echo -e "${YELLOW}✗ Connected but DDC/CI not supported${NC}"
                echo "   (Likely using HDMI on Apple Silicon or DDC/CI disabled)"
            else
                local lum=$(echo "$result" | grep -oE '[0-9]+' | head -1)
                if [ -n "$lum" ]; then
                    echo -e "${GREEN}✓ DDC/CI supported (brightness: $lum%)${NC}"
                    found_any=true
                else
                    echo -e "${YELLOW}✗ No valid DDC/CI response${NC}"
                fi
            fi
        else
            if ddcctl -d "$d" 2>/dev/null | grep -q "Display"; then
                echo -e "${GREEN}✓ DDC/CI supported${NC}"
                found_any=true
            else
                echo -e "${YELLOW}✗ Connected but DDC/CI not supported${NC}"
            fi
        fi
    done

    echo ""
    if [ "$found_any" = true ]; then
        echo -e "${GREEN}✓ Found DDC/CI-capable displays!${NC}"
        echo ""
        echo "Next step: Run './switch.sh setup' to configure input switching"
    else
        echo -e "${RED}✗ No DDC/CI-capable displays found.${NC}"
        echo ""
        echo "Possible reasons:"
        echo "  • Using HDMI on Apple Silicon Macs (not supported)"
        echo "  • DDC/CI disabled in monitor's OSD menu"
        echo "  • Cable or adapter doesn't support DDC/CI"
        echo ""
        echo "Recommendations:"
        echo "  ✓ Use Thunderbolt/USB-C to DisplayPort cable"
        echo "  ✓ Enable DDC/CI in your monitor's settings menu"
    fi
    echo ""
}

function _ddc_set_input() {
    local d=$1 input_value=$2
    local result status=0
    if [ "$DDC_TOOL" = "m1ddc" ]; then
        result=$(m1ddc display "$d" set input "$input_value" 2>&1) || status=$?
    else
        result=$(ddcctl -d "$d" -i "$input_value" 2>&1) || status=$?
    fi
    echo "$result"
    if [ "$status" -ne 0 ] || echo "$result" | grep -qi "failure\|failed\|error\|not found\|no display"; then
        echo "ERROR: DDC set failed for Display $d input $input_value"
    fi
    return 0
}

function _ddc_probe() {
    local d=$1
    if [ "$DDC_TOOL" = "m1ddc" ]; then
        m1ddc display "$d" get luminance 2>&1 || true
    else
        ddcctl -d "$d" 2>&1 || true
    fi
}

function _get_connected_displays() {
    # Get list of actually connected displays from m1ddc/ddcctl
    local _var_name=$1
    local _temp_array=()
    
    if [ "$DDC_TOOL" = "m1ddc" ]; then
        # Parse m1ddc display list output
        # Possible formats:
        # "Display 1: <name>"
        # "1: <name>"
        # Or just count how many displays are listed
        local list_output
        list_output=$(m1ddc display list 2>&1 || true)
        
        # Debug: uncomment to see raw output
        # echo "DEBUG: m1ddc output:"
        # echo "$list_output"
        # echo "---"
        
        # Try to extract display IDs from the output
        # Look for lines containing "Display N" or just "N:"
        local found_count=0
        while IFS= read -r line; do
            # Match "Display 1:" or "1:" at start of line
            if echo "$line" | grep -qE '^\s*(Display\s+)?[0-9]+\s*:'; then
                local id=$(echo "$line" | grep -oE '[0-9]+' | head -1)
                if [ -n "$id" ] && [ "$id" -le 6 ]; then
                    # Avoid duplicates
                    local already_added=false
                    for existing in "${_temp_array[@]}"; do
                        if [ "$existing" = "$id" ]; then
                            already_added=true
                            break
                        fi
                    done
                    if [ "$already_added" = false ]; then
                        _temp_array+=("$id")
                        ((found_count++))
                    fi
                fi
            fi
        done <<< "$list_output"
        
        # If we didn't find any displays in the list output, try counting display references
        if [ "$found_count" -eq 0 ]; then
            # Count how many times "display" appears (case insensitive)
            local display_count=$(echo "$list_output" | grep -i -c "display" || echo "0")
            if [ "$display_count" -gt 0 ] && [ "$display_count" -le 6 ]; then
                # Assume displays are numbered 1, 2, 3, ... up to display_count
                for ((i=1; i<=display_count; i++)); do
                    _temp_array+=("$i")
                done
            fi
        fi
    fi
    
    # If we still got nothing, fall back to probing 1-6
    if [ "${#_temp_array[@]}" -eq 0 ]; then
        # Fallback: probe 1-6
        for d in 1 2 3 4 5 6; do
            _temp_array+=("$d")
        done
    fi
    
    eval "$_var_name=(\"\${_temp_array[@]}\")"
}

function _find_responsive_displays() {
    local _var_name=$1
    local _temp_array=()
    local _connected_displays=()
    
    # First, get the list of connected displays
    _get_connected_displays _connected_displays
    
    echo "Scanning for DDC/CI-capable displays..."
    echo "Connected displays: ${_connected_displays[*]}"
    echo ""
    
    for d in "${_connected_displays[@]}"; do
        echo -n "  Display ID $d: "
        local probe_result
        probe_result=$(_ddc_probe "$d")
        
        # Check if DDC/CI is working
        if echo "$probe_result" | grep -qi "failure\|not found\|no display\|error\|disabled"; then
            echo -e "${YELLOW}✗ Connected but DDC/CI not supported${NC}"
        else
            # Verify we got a valid response (contains a number for luminance)
            if echo "$probe_result" | grep -qE '[0-9]+'; then
                echo -e "${GREEN}✓ DDC/CI supported${NC}"
                _temp_array+=("$d")
            else
                echo -e "${YELLOW}✗ No valid DDC/CI response${NC}"
            fi
        fi
    done
    echo ""
    
    eval "$_var_name=(\"\${_temp_array[@]}\")"
}

function switch_profile() {
    local profile=$1

    if [ -z "$profile" ]; then
        echo -e "${RED}Error: Profile name required${NC}"
        print_usage
        exit 1
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}Error: Config not found: $CONFIG_FILE${NC}" >&2
        echo -e "${YELLOW}Run './switch.sh setup' to auto-configure.${NC}" >&2
        exit 1
    fi

    echo "Switching monitors to profile '$profile'"
    echo "Using tool: $DDC_TOOL"
    echo ""

    local success=0
    local failure=0

    # Check if profile uses per-monitor format (object) or legacy format (string)
    local is_per_monitor=false
    if [ "$USE_JQ" = true ]; then
        local profile_type
        profile_type=$(jq -r ".profiles[\"$profile\"] | type" "$CONFIG_FILE")
        if [ "$profile_type" = "null" ]; then
            echo -e "${RED}Error: Profile '$profile' not found in config.${NC}" >&2
            exit 1
        fi
        [ "$profile_type" = "object" ] && is_per_monitor=true
    fi

    if [ "$is_per_monitor" = true ]; then
        # Per-monitor format: { "0": "dp1", "1": "hdmi2" }
        local display_list=()
        _find_responsive_displays display_list

        local monitor_ids
        monitor_ids=$(jq -r ".profiles[\"$profile\"] | keys[]" "$CONFIG_FILE" | sort -n)
        for mon_id in $monitor_ids; do
            if [ "$mon_id" -ge "${#display_list[@]}" ]; then
                echo -e "Config monitor $mon_id: ${YELLOW}skipped (no matching display)${NC}"
                ((failure++)) || true
                continue
            fi
            local d="${display_list[$mon_id]}"
            local input_name
            input_name=$(jq -r ".profiles[\"$profile\"][\"$mon_id\"]" "$CONFIG_FILE")
            local input_value
            input_value=$(jq -r ".inputs[\"$input_name\"]" "$CONFIG_FILE")
            if [ "$input_value" = "null" ] || [ -z "$input_value" ]; then
                echo -e "Display $d: ${RED}unknown input '$input_name'${NC}"
                ((failure++)) || true
                continue
            fi

            echo -n "Display $d ($input_name -> $input_value): "
            local switch_result
            switch_result=$(_ddc_set_input "$d" "$input_value")

            if echo "$switch_result" | grep -qi "failure\|error"; then
                echo -e "${RED}FAILED${NC}"
                ((failure++)) || true
            else
                echo -e "${GREEN}OK${NC}"
                ((success++)) || true
            fi
        done
    else
        # Legacy format: single input value for all monitors
        local input_value
        input_value=$(load_config "$profile")
        if [ -z "$input_value" ]; then
            echo -e "${RED}Error: Could not determine input value for profile '$profile'${NC}"
            exit 1
        fi
        echo "All monitors -> input value $input_value"

        for d in 1 2 3 4; do
            local probe_result
            probe_result=$(_ddc_probe "$d")
            if echo "$probe_result" | grep -qi "failure\|not found\|no display"; then
                continue
            fi

            echo -n "Display $d: "
            local switch_result
            switch_result=$(_ddc_set_input "$d" "$input_value")

            if echo "$switch_result" | grep -qi "failure\|error"; then
                echo -e "${RED}FAILED${NC}"
                ((failure++)) || true
            else
                echo -e "${GREEN}OK${NC}"
                ((success++)) || true
            fi
        done
    fi

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

function auto_input_key() {
    case "$1" in
        3)  echo "dvi1" ;;
        4)  echo "dvi2" ;;
        15) echo "dp1" ;;
        16) echo "dp2" ;;
        17) echo "hdmi1" ;;
        18) echo "hdmi2" ;;
        19) echo "hdmi3" ;;
        27) echo "usbc" ;;
        *)  echo "input$1" ;;
    esac
}

function blink_monitor() {
    local d=$1
    local original_lum="50"

    if [ "$DDC_TOOL" = "m1ddc" ]; then
        original_lum=$(m1ddc display "$d" get luminance 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "50")
        echo -n "  Blinking display $d"
        for i in 1 2 3 4 5; do
            m1ddc display "$d" set luminance 0 &>/dev/null || true
            sleep 0.4
            m1ddc display "$d" set luminance 100 &>/dev/null || true
            sleep 0.4
            echo -n "."
        done
        m1ddc display "$d" set luminance "$original_lum" &>/dev/null || true
        echo " done"
    else
        original_lum=$(ddcctl -d "$d" 2>/dev/null | grep -i "luminance\|brightness" | grep -oE '[0-9]+' | head -1 || echo "50")
        echo -n "  Blinking display $d"
        for i in 1 2 3 4 5; do
            ddcctl -d "$d" -b 0 &>/dev/null || true
            sleep 0.4
            ddcctl -d "$d" -b 100 &>/dev/null || true
            sleep 0.4
            echo -n "."
        done
        ddcctl -d "$d" -b "$original_lum" &>/dev/null || true
        echo " done"
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

function get_vcp() {
    local d=$1
    local vcp_code=${2:-60}

    if [ "$vcp_code" != "60" ]; then
        echo -e "${RED}Error: macOS wrapper only supports VCP 60/input source${NC}" >&2
        exit 1
    fi

    local code
    code=$(get_current_input "$d")
    if [ -z "$code" ] || [ "$code" = "0" ]; then
        echo -e "${RED}Error: Could not read current input for Display $d${NC}" >&2
        exit 1
    fi

    echo "VCP 0x60: $code ($code decimal)"
}

function set_vcp() {
    local d=$1
    local vcp_code=${2:-60}
    local value=$3

    if [ "$vcp_code" != "60" ]; then
        echo -e "${RED}Error: macOS wrapper only supports VCP 60/input source${NC}" >&2
        exit 1
    fi
    if [ -z "$value" ]; then
        echo -e "${RED}Error: Missing VCP value${NC}" >&2
        exit 1
    fi

    local result
    result=$(_ddc_set_input "$d" "$value")
    echo "$result" >&2
    if echo "$result" | grep -qi "failure\|failed\|error\|not found\|no display"; then
        exit 1
    fi
    echo "OK: Display $d VCP 0x60 set to $value"
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
    # Args: num_monitors mon_name_0 ... num_inputs inp_name_0 inp_code_0 ... num_profiles prof_name_0 mon0_input ... prof_name_1 mon0_input ...
    local num_monitors=$1; shift
    local mon_names=()
    for ((i=0; i<num_monitors; i++)); do
        mon_names+=("$1"); shift
    done

    local num_inputs=$1; shift
    local inp_names=()
    local inp_codes=()
    for ((i=0; i<num_inputs; i++)); do
        inp_names+=("$1"); shift
        inp_codes+=("$1"); shift
    done

    local num_profiles=$1; shift

    {
        printf '{\n'
        printf '  "vcp_code": "0x60",\n'

        # monitors
        printf '  "monitors": [\n'
        for ((i=0; i<num_monitors; i++)); do
            printf '    {"id": %d, "name": "%s"}' "$i" "${mon_names[$i]}"
            [ $((i+1)) -lt "$num_monitors" ] && printf ','
            printf '\n'
        done
        printf '  ],\n'

        # inputs
        printf '  "inputs": {\n'
        for ((i=0; i<num_inputs; i++)); do
            printf '    "%s": %d' "${inp_names[$i]}" "${inp_codes[$i]}"
            [ $((i+1)) -lt "$num_inputs" ] && printf ','
            printf '\n'
        done
        printf '  },\n'

        # profiles
        printf '  "profiles": {\n'
        for ((p=0; p<num_profiles; p++)); do
            local prof_name=$1; shift
            printf '    "%s": {\n' "$prof_name"
            for ((m=0; m<num_monitors; m++)); do
                local inp=$1; shift
                printf '      "%d": "%s"' "$m" "$inp"
                [ $((m+1)) -lt "$num_monitors" ] && printf ','
                printf '\n'
            done
            printf '    }'
            [ $((p+1)) -lt "$num_profiles" ] && printf ','
            printf '\n'
        done
        printf '  }\n'
        printf '}\n'
    } > "$CONFIG_FILE"

    echo -e "${GREEN}Config written to: $CONFIG_FILE${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Bash 3.2 compatible associative array helpers (using indexed arrays)
# ─────────────────────────────────────────────────────────────────────────────

function _assoc_set() {
    # Usage: _assoc_set array_name key value
    local _arr_name=$1
    local _key=$2
    local _value=$3
    local _escaped_key=${_key//\\/\\\\}
    _escaped_key=${_escaped_key//=/\\=}
    
    # Remove old entry if exists
    eval "
    local _tmp=()
    for _item in \"\${${_arr_name}[@]}\"; do
        if [[ \"\$_item\" != \"${_escaped_key}=\"* ]]; then
            _tmp+=(\"\$_item\")
        fi
    done
    _tmp+=(\"${_escaped_key}=${_value}\")
    ${_arr_name}=(\"\${_tmp[@]}\")
    "
}

function _assoc_get() {
    # Usage: result=$(_assoc_get array_name key)
    local _arr_name=$1
    local _key=$2
    local _escaped_key=${_key//\\/\\\\}
    _escaped_key=${_escaped_key//=/\\=}
    
    eval "
    for _item in \"\${${_arr_name}[@]}\"; do
        if [[ \"\$_item\" == \"${_escaped_key}=\"* ]]; then
            echo \"\${_item#*=}\"
            return 0
        fi
    done
    "
}

function _assoc_keys() {
    # Usage: keys_array=($(_assoc_keys array_name))
    local _arr_name=$1
    eval "
    for _item in \"\${${_arr_name}[@]}\"; do
        echo \"\${_item%%=*}\"
    done
    "
}

function _assoc_has_key() {
    # Usage: _assoc_has_key array_name key && ...
    local _arr_name=$1
    local _key=$2
    local _escaped_key=${_key//\\/\\\\}
    _escaped_key=${_escaped_key//=/\\=}
    
    eval "
    for _item in \"\${${_arr_name}[@]}\"; do
        if [[ \"\$_item\" == \"${_escaped_key}=\"* ]]; then
            return 0
        fi
    done
    return 1
    "
}

function setup_wizard() {
    echo ""
    echo "=============================="
    echo " Monitor Setup Wizard"
    echo "=============================="
    echo ""

    # Get all connected displays first
    local all_connected_displays=()
    _get_connected_displays all_connected_displays
    
    echo "Connected displays detected: ${all_connected_displays[*]}"
    echo ""
    
    # Find which ones support DDC/CI
    local display_list=()
    _find_responsive_displays display_list

    if [ "${#display_list[@]}" -eq 0 ]; then
        echo -e "${RED}Error: No DDC/CI-capable displays found.${NC}"
        echo ""
        echo "All ${#all_connected_displays[@]} connected display(s) lack DDC/CI support."
        echo ""
        echo "Common causes:"
        echo "  - Monitors are connected via Thunderbolt/USB-C (not HDMI on Apple Silicon)"
        echo "  - DDC/CI is enabled in each monitor's OSD menu"
        echo "  - Cable or hub doesn't support DDC/CI protocol"
        echo ""
        echo "You can still use manual mode to see all displays,"
        echo "but only DDC/CI-capable displays can be controlled."
        exit 1
    fi

    echo -e "${GREEN}DDC/CI-capable displays: ${#display_list[@]} of ${#all_connected_displays[@]}${NC}"
    echo "Controllable IDs: ${display_list[*]}"
    
    # Show which displays are not controllable
    local non_ddc_displays=()
    for d in "${all_connected_displays[@]}"; do
        local found=false
        for dd in "${display_list[@]}"; do
            if [ "$d" = "$dd" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            non_ddc_displays+=("$d")
        fi
    done
    
    if [ "${#non_ddc_displays[@]}" -gt 0 ]; then
        echo -e "${YELLOW}Non-controllable IDs: ${non_ddc_displays[*]} (DDC/CI not supported)${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Note about Display IDs:${NC}"
    echo "  IDs may not be consecutive (e.g., 1, 3, 4 instead of 1, 2, 3)."
    echo "  This is normal - macOS assigns IDs based on connection order."
    echo ""
    echo -e "${YELLOW}Cable compatibility:${NC}"
    echo "  ✓ Thunderbolt/USB-C to DP: Full DDC/CI support"
    echo "  ✓ USB-C hub to DP/HDMI: May work (depends on hub chipset)"
    echo "  ✗ HDMI on Apple Silicon: Usually NO DDC/CI support"
    echo ""

    # Phase A: identify each display by blinking
    local monitor_names=()
    local active_displays=()  # Only displays that user confirmed (not skipped)
    
    echo "═══════════════════════════════════════════════════════"
    echo "Phase 1: Display Identification"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "Available options:"
    echo "  • Enter a name (e.g., 'Left', 'Right', 'Center') if you see flashing"
    echo "  • Type 'skip' if you don't see any flash (cable may not support DDC/CI)"
    echo "  • Type 'manual' to directly enter display ID numbers"
    echo ""
    
    read -r -p "How would you like to identify monitors? (auto/manual) [auto]: " id_mode
    id_mode=${id_mode:-auto}
    echo ""
    
    if [ "$id_mode" = "manual" ] || [ "$id_mode" = "m" ]; then
        # Manual mode: user directly enters display IDs and names
        echo "Manual mode: Enter display IDs and names directly."
        echo ""
        echo "All connected displays:"
        for d in "${all_connected_displays[@]}"; do
            # Check if this display supports DDC/CI
            local supports_ddc=false
            for dd in "${display_list[@]}"; do
                if [ "$d" = "$dd" ]; then
                    supports_ddc=true
                    break
                fi
            done
            
            if [ "$supports_ddc" = true ]; then
                echo -e "  Display $d: ${GREEN}✓ DDC/CI supported (can be configured)${NC}"
            else
                echo -e "  Display $d: ${YELLOW}✗ DDC/CI not supported (cannot be controlled)${NC}"
            fi
        done
        echo ""
        echo "You can only configure DDC/CI-capable displays: ${display_list[*]}"
        echo ""
        
        for d in "${display_list[@]}"; do
            local name_input
            read -r -p "Configure display $d? Enter name or 'skip': " name_input
            
            if [ "$name_input" = "skip" ] || [ "$name_input" = "s" ]; then
                echo -e "${YELLOW}  Skipping Display $d${NC}"
            else
                if [ -z "$name_input" ]; then name_input="Display$d"; fi
                _assoc_set monitor_names "$d" "$name_input"
                active_displays+=("$d")
                echo -e "${GREEN}  ✓ Display $d: $name_input${NC}"
            fi
            echo ""
        done
    else
        # Auto mode with blinking
        for d in "${display_list[@]}"; do
            echo "─────────────────────────────────────"
            echo "Testing Display ID: $d"
            echo "─────────────────────────────────────"
            echo "Watch your monitors carefully..."
            echo ""
            blink_monitor "$d"
            echo ""
            local name_input
            read -r -p "Which monitor flashed? (Enter name, or 'skip'): " name_input
            
            if [ "$name_input" = "skip" ] || [ "$name_input" = "s" ]; then
                echo -e "${YELLOW}  ✗ Skipping Display $d (will not be configured)${NC}"
            else
                if [ -z "$name_input" ]; then name_input="Display$d"; fi
                _assoc_set monitor_names "$d" "$name_input"
                active_displays+=("$d")
                echo -e "${GREEN}  ✓ Display $d: $name_input${NC}"
            fi
            echo ""
        done
    fi
    
    # Update display_list to only include active displays
    display_list=("${active_displays[@]}")
    
    if [ "${#display_list[@]}" -eq 0 ]; then
        echo -e "${RED}Error: No displays confirmed. Setup cancelled.${NC}"
        echo "Make sure monitors are connected via cables that support DDC/CI"
        echo "(Thunderbolt/USB-C/DisplayPort, not HDMI on Apple Silicon)."
        exit 1
    fi
    
    echo -e "${GREEN}Proceeding with ${#display_list[@]} confirmed display(s).${NC}"
    echo ""

    # Phase B: interactive probe — for each monitor, let user try VCP codes
    echo "═══════════════════════════════════════════════════════"
    echo "Phase 2: Input Source Detection"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo -e "${YELLOW}Important:${NC}"
    echo "  We need to identify which VCP code corresponds to THIS Mac system."
    echo "  The detected value is usually correct - just press Enter to use it."
    echo ""
    echo -e "${YELLOW}  WARNING: Testing wrong codes will temporarily switch your monitor away!${NC}"
    echo "  Only test if you're sure the detected value is wrong."
    echo ""
    
    local candidate_codes=(15 16 17 18 19 3 4 27)
    local confirmed_codes=()  # display_id -> confirmed VCP code

    for d in "${display_list[@]}"; do
        local current
        current=$(get_current_input "$d")

        echo "───────────────────────────────────────────────────────"
        echo "Display: $(_assoc_get monitor_names "$d") (ID: $d)"
        echo "───────────────────────────────────────────────────────"
        echo ""
        echo -e "${GREEN}Detected current input: $current ($(known_input_name "$current"))${NC}"
        echo ""
        echo "Common VCP codes for reference:"
        for c in "${candidate_codes[@]}"; do
            if [ "$c" = "$current" ]; then
                printf "  ${GREEN}%2d - %s ← DETECTED${NC}\n" "$c" "$(known_input_name "$c")"
            else
                printf "  %2d - %s\n" "$c" "$(known_input_name "$c")"
            fi
        done
        echo ""
        echo "Options:"
        echo "  • Press ENTER to use detected value $current (recommended)"
        echo "  • Enter a code number to test it (screen may go black temporarily!)"
        echo ""

        while true; do
            read -r -p "Your choice [Enter=$current]: " line

            # Default to current if empty
            if [ -z "$line" ]; then
                _assoc_set confirmed_codes "$d" "$current"
                echo -e "${GREEN}  ✓ Using detected value: $current ($(known_input_name "$current"))${NC}"
                break
            fi

            # Validate input is a number
            if ! [[ "$line" =~ ^[0-9]+$ ]]; then
                echo -e "${YELLOW}  Invalid input. Enter a number or press Enter.${NC}"
                continue
            fi

            local test_code="$line"
            
            echo ""
            echo -e "${YELLOW}═══ WARNING ═══${NC}"
            echo "  Testing code $test_code ($(known_input_name "$test_code"))"
            echo -e "${YELLOW}  Your screen may go BLACK or switch to another system!${NC}"
            echo -e "${YELLOW}  It will AUTO-RESTORE in 3 seconds - DO NOT TOUCH ANYTHING!${NC}"
            echo ""
            read -r -p "Continue with this test? (y/n): " confirm
            
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "  Test cancelled."
                continue
            fi
            
            echo ""
            echo "  Switching to code $test_code in:"
            echo -n "  3..."
            sleep 1
            echo -n " 2..."
            sleep 1
            echo " 1..."
            sleep 1
            
            _ddc_set_input "$d" "$test_code" > /dev/null 2>&1
            
            echo -n "  [Testing for 3 seconds"
            for i in 1 2 3; do
                sleep 1
                echo -n "."
            done
            echo "]"
            
            # Auto-restore
            _ddc_set_input "$d" "$current" > /dev/null 2>&1
            sleep 1
            
            echo ""
            echo -e "${GREEN}  ✓ Restored to original input${NC}"
            echo ""
            echo "What happened during the test?"
            echo "  1) Screen stayed NORMAL (no change) → code $test_code is CORRECT"
            echo "  2) Screen went BLACK or switched away → code $test_code is WRONG"
            echo ""
            read -r -p "Did the screen stay normal? (y/n): " yn
            
            if [ "$yn" = "y" ] || [ "$yn" = "Y" ]; then
                _assoc_set confirmed_codes "$d" "$test_code"
                echo -e "${GREEN}  ✓ Confirmed: code $test_code ($(known_input_name "$test_code"))${NC}"
                break
            else
                echo -e "${YELLOW}  ✗ Code $test_code is incorrect. Try another or press Enter for $current.${NC}"
                echo ""
            fi
        done
        echo ""
    done

    # Phase C: ask profile name for this system
    echo "─────────────────────────────────────"
    read -r -p "Profile name for this system (e.g. 'mac', 'windows', 'linux'): " profile_name
    if [ -z "$profile_name" ]; then
        echo "Profile name cannot be empty. Setup cancelled."
        exit 1
    fi
    echo ""

    # Phase D: merge with existing config
    local input_map=()  # key_name -> code

    if [ -f "$CONFIG_FILE" ] && [ "$USE_JQ" = true ]; then
        echo "Existing config found. Will merge."
        local existing_keys
        existing_keys=$(jq -r '.inputs | keys[]' "$CONFIG_FILE" 2>/dev/null || true)
        for key in $existing_keys; do
            local val
            val=$(jq -r ".inputs[\"$key\"]" "$CONFIG_FILE")
            if [ "$val" != "null" ] && [ -n "$val" ]; then
                _assoc_set input_map "$key" "$val"
            fi
        done
    fi

    # Build profile from confirmed codes, auto-name inputs
    local new_profile=()  # monitor_index -> input_key
    local mon_idx=0
    local num_monitors=${#display_list[@]}

    for d in "${display_list[@]}"; do
        local code
        code=$(_assoc_get confirmed_codes "$d")
        if [ -z "$code" ] || [ "$code" = "0" ]; then
            echo -e "${YELLOW}Warning: No confirmed code for Display $d, skipping.${NC}"
            ((mon_idx++)) || true
            continue
        fi

        # Find existing input name for this code
        local input_key=""
        for key in $(_assoc_keys input_map); do
            local val
            val=$(_assoc_get input_map "$key")
            if [ "$val" = "$code" ]; then
                input_key="$key"
                break
            fi
        done

        # Auto-name if not found
        if [ -z "$input_key" ]; then
            input_key=$(auto_input_key "$code")
            while _assoc_has_key input_map "$input_key"; do
                local existing_val
                existing_val=$(_assoc_get input_map "$input_key")
                [ "$existing_val" = "$code" ] && break
                input_key="${input_key}_"
            done
            _assoc_set input_map "$input_key" "$code"
        fi

        _assoc_set new_profile "$mon_idx" "$input_key"
        ((mon_idx++)) || true
    done

    # Phase E: preview and confirm
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "Configuration Preview"
    echo "═══════════════════════════════════════════════════════"
    echo ""
    echo "VCP Code: 0x60 (Input Source)"
    echo ""
    echo "Monitors:"
    local idx=0
    for d in "${display_list[@]}"; do
        printf "  [%d] %s (Display ID: %d)\n" "$idx" "$(_assoc_get monitor_names "$d")" "$d"
        ((idx++)) || true
    done
    echo ""
    echo "Input Codes:"
    for key in $(_assoc_keys input_map); do
        local val
        val=$(_assoc_get input_map "$key")
        printf "  %-12s → VCP value %s (%s)\n" "$key" "$val" "$(known_input_name "$val")"
    done
    echo ""
    echo "Profiles:"
    if [ -f "$CONFIG_FILE" ] && [ "$USE_JQ" = true ]; then
        local existing_profiles
        existing_profiles=$(jq -r '.profiles | keys[]' "$CONFIG_FILE" 2>/dev/null || true)
        for prof in $existing_profiles; do
            if [ "$prof" != "$profile_name" ]; then
                echo "  • $prof: (kept from existing config)"
            fi
        done
    fi
    echo "  • $profile_name: (NEW)"
    for ((i=0; i<num_monitors; i++)); do
        local d="${display_list[$i]}"
        printf "      [%d] %s → %s\n" "$i" "$(_assoc_get monitor_names "$d")" "$(_assoc_get new_profile "$i")"
    done
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo ""

    read -r -p "Save this configuration to $CONFIG_FILE? (y/n): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${YELLOW}Setup cancelled.${NC}"
        exit 1
    fi

    # Write config
    if [ "$USE_JQ" = true ] && [ -f "$CONFIG_FILE" ]; then
        # Merge with existing using jq
        local monitors_json="["
        idx=0
        for d in "${display_list[@]}"; do
            [ "$idx" -gt 0 ] && monitors_json+=","
            monitors_json+="{\"id\":$idx,\"name\":\"$(_assoc_get monitor_names "$d")\"}"
            ((idx++)) || true
        done
        monitors_json+="]"

        local inputs_json="{"
        local first=true
        for key in $(_assoc_keys input_map); do
            [ "$first" = true ] && first=false || inputs_json+=","
            local val
            val=$(_assoc_get input_map "$key")
            inputs_json+="\"$key\":${val}"
        done
        inputs_json+="}"

        local new_prof_json="{"
        first=true
        for ((i=0; i<num_monitors; i++)); do
            [ "$first" = true ] && first=false || new_prof_json+=","
            new_prof_json+="\"$i\":\"$(_assoc_get new_profile "$i")\""
        done
        new_prof_json+="}"

        jq --argjson monitors "$monitors_json" \
           --argjson inputs "$inputs_json" \
           --arg prof_name "$profile_name" \
           --argjson new_prof "$new_prof_json" \
           '. | .monitors = $monitors | .inputs = $inputs | .profiles[$prof_name] = $new_prof' \
           "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    else
        # Fresh config
        local write_args=()
        write_args+=("$num_monitors")
        for d in "${display_list[@]}"; do
            write_args+=("$(_assoc_get monitor_names "$d")")
        done
        local all_keys=($(_assoc_keys input_map))
        write_args+=("${#all_keys[@]}")
        for key in "${all_keys[@]}"; do
            local val
            val=$(_assoc_get input_map "$key")
            write_args+=("$key" "$val")
        done
        write_args+=("1")
        local profile_inputs=()
        for ((i=0; i<num_monitors; i++)); do
            profile_inputs+=("$(_assoc_get new_profile "$i")")
        done
        write_args+=("$profile_name" "${profile_inputs[@]}")
        write_config "${write_args[@]}"
    fi

    echo ""
    echo -e "${GREEN}✓ Configuration saved to: $CONFIG_FILE${NC}"
    echo ""
    echo "─────────────────────────────────────────────────────"
    echo -e "${GREEN}Setup complete!${NC}"
    echo "─────────────────────────────────────────────────────"
    if [ -f "$CONFIG_FILE" ] && [ "$USE_JQ" = true ]; then
        local prof_count
        prof_count=$(jq '.profiles | length' "$CONFIG_FILE" 2>/dev/null || echo "1")
        if [ "$prof_count" -lt 2 ]; then
            echo ""
            echo -e "${YELLOW}Note: You currently have only 1 profile configured.${NC}"
            echo "      Run './switch.sh setup' on your other system to add its profile."
            echo ""
        fi
    fi
    echo "To test the configuration, run:"
    echo -e "${GREEN}  ./switch.sh $profile_name${NC}"
    echo ""
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
    getvcp)
        if [ $# -lt 3 ]; then
            echo -e "${RED}Usage: $0 getvcp <display_id> <vcp_code>${NC}" >&2
            exit 1
        fi
        get_vcp "$2" "$3"
        ;;
    setvcp)
        if [ $# -lt 4 ]; then
            echo -e "${RED}Usage: $0 setvcp <display_id> <vcp_code> <value>${NC}" >&2
            exit 1
        fi
        set_vcp "$2" "$3" "$4"
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
