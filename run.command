#!/bin/bash
cd "$(dirname "$0")"
nohup python3 -m monitor_hub > /dev/null 2>&1 &
