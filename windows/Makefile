# Simple Makefile for MinGW-w64
# Usage: mingw32-make

CXX = g++
CXXFLAGS = -std=c++17 -O2 -Wall -static
LDFLAGS = -ldxva2 -lgdi32 -luser32
BINDIR = ../bin
TARGET = $(BINDIR)/monitor_switcher.exe
SRC = monitor_switcher.cpp

all: $(TARGET)

$(TARGET): $(SRC)
	@if not exist "$(BINDIR)" mkdir "$(BINDIR)"
	$(CXX) $(CXXFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)
	@echo Build complete: $(TARGET)

clean:
	del /f "$(TARGET)" 2>nul || echo Nothing to clean

test: $(TARGET)
	$(TARGET) help

.PHONY: all clean test
