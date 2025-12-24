#!/bin/bash
# Build the ndsplib-hifi5 library and export it with public header files
#
# Usage: ./build_ndsplib_hifi5.sh [-v|--version <version>] [-m|--mem-model <1|2>] [-c|--clean]
#
# This script will:
# 1. Extract the NDSP library source from the zip archive
# 2. Build the library using the Xtensa toolchain
# 3. Export the library and public headers to a pkg/ folder

set -e  # Exit on error

# Default values
VERSION="v280"
MEM_MODEL=1
CLEAN_BUILD=0

# Parse command line arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -m|--mem-model)
            if [ -n "$2" ] && [[ "$2" =~ ^[12]$ ]]; then
                MEM_MODEL="$2"
                shift 2
            else
                echo "Error: Invalid memory model. Use 1 or 2." >&2
                exit 1
            fi
            ;;
        -c|--clean)
            CLEAN_BUILD=1
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--version <version>] [-m|--mem-model <1|2>] [-c|--clean]"
            echo ""
            echo "Options:"
            echo "  -v, --version <version>    NDSP version (280, 270, 300, 310) [default: 280]"
            echo "  -m, --mem-model <1|2>      Memory model [default: 1]"
            echo "  -c, --clean                Clean build (remove previous build artifacts)"
            echo "  -h, --help                 Show this help message"
            echo ""
            echo "Environment variables required:"
            echo "  XTENSA_CORE     - HiFi core name (e.g., hifi5s_ao_7)"
            echo "  XTENSA_SYSTEM   - Path to Xtensa tools"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Use -h or --help for usage information." >&2
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "NDSP HiFi5 Library Build Script"
echo "=========================================="
echo "Version: $VERSION"
echo "Memory Model: $MEM_MODEL"
echo "Clean Build: $([ $CLEAN_BUILD -eq 1 ] && echo 'Yes' || echo 'No')"
echo "=========================================="

# Check if XTENSA_CORE is set
if [ -z "$XTENSA_CORE" ]; then
    echo "Error: XTENSA_CORE environment variable is not set." >&2
    echo "Please set it to your HiFi core name (e.g., hifi5s_ao_7)" >&2
    exit 1
fi

echo "XTENSA_CORE: $XTENSA_CORE"
echo "XTENSA_SYSTEM: ${XTENSA_SYSTEM:-not set}"
echo ""

# Determine archive name based on version
ARCHIVE_NAME="NDSP_HiFi5_${VERSION}.zip"
EXTRACT_DIR="NDSP_HiFi5_${VERSION}"
ARCHIVE_PATH="NDSP_HiFi5/${ARCHIVE_NAME}"
# Check if archive exists
if [ ! -f "$ARCHIVE_PATH" ]; then
    echo "Error: Archive not found: $ARCHIVE_PATH" >&2
    exit 1
fi

# Clean previous build if requested
if [ $CLEAN_BUILD -eq 1 ]; then
    echo "Cleaning previous build artifacts..."
    rm -rf "NDSP_HiFi5/${EXTRACT_DIR}"
    rm -rf pkg
    echo "✓ Clean completed"
fi

# Extract the archive
echo ""
echo "Extracting $ARCHIVE_NAME..."
cd NDSP_HiFi5
unzip -q -o "$ARCHIVE_NAME"
if [ $? -ne 0 ]; then
    echo "Error: Failed to extract archive" >&2
    exit 1
fi
cd ..
echo "✓ Archive extracted successfully"

# Check if build directory exists
BUILD_DIR="NDSP_HiFi5/${EXTRACT_DIR}/build/project/xtclang/library"
if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found: $BUILD_DIR" >&2
    echo "The archive structure may have changed." >&2
    exit 1
fi

# Navigate to build directory and build the library
echo ""
echo "Building library (MEM_MODEL=$MEM_MODEL)..."
echo "This may take several minutes..."
cd "$BUILD_DIR"

# Clean previous builds
if [ $CLEAN_BUILD -eq 1 ]; then
    make clean -j 2>&1 | tee build_clean.log
fi

# Build the library
make all -j MEM_MODEL=$MEM_MODEL
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo ""
    echo "Error: Build failed. Check build.log for details." >&2
    echo "Log location: $(pwd)/build.log" >&2
    exit 1
fi

# Return to the root directory
cd - > /dev/null

echo ""
echo "✓ Build completed successfully!"
# # Create pkg directory structure
echo ""
echo "Creating package directory structure..."
PKG_DIR="pkg"
PKG_INCLUDE_DIR="$PKG_DIR/include"
PKG_LIB_DIR="$PKG_DIR/lib"

mkdir -p "$PKG_INCLUDE_DIR"
mkdir -p "$PKG_LIB_DIR"
# Copy public header files
echo "Copying public header files..."
HEADER_SRC_DIR="NDSP_HiFi5/${EXTRACT_DIR}/library/include"

if [ ! -d "$HEADER_SRC_DIR" ]; then
    echo "Error: Header directory not found: $HEADER_SRC_DIR" >&2
    exit 1
fi

cp -v "$HEADER_SRC_DIR"/*.h "$PKG_INCLUDE_DIR/"
echo "✓ Headers copied to $PKG_INCLUDE_DIR/"

# Copy the built library
echo ""
echo "Copying library file..."
LIB_SRC_DIR="NDSP_HiFi5/${EXTRACT_DIR}/build/bin"

# Find the library file (it will have the core name in it)
LIB_FILE=$(find "$LIB_SRC_DIR" -name "NatureDSP_Signal*.a" -type f | head -1)
if [ -z "$LIB_FILE" ]; then
    echo "Error: Library file not found in $LIB_SRC_DIR" >&2
    echo "Expected pattern: NatureDSP_Signal*.a" >&2
    exit 1
fi

cp -v "$LIB_FILE" "$PKG_LIB_DIR/"
echo "✓ Library copied to $PKG_LIB_DIR/"
# Create a symlink with a generic name for easier linking
LIB_BASENAME=$(basename "$LIB_FILE")
cd "$PKG_LIB_DIR"
ln -sf "$LIB_BASENAME" "libndsp_hifi5.a"
cd - > /dev/null

echo ""
echo "=========================================="
echo "Build Summary"
echo "=========================================="
echo "Package location: $(pwd)/$PKG_DIR"
echo ""
echo "Headers:"
ls -1 "$PKG_INCLUDE_DIR"/*.h | wc -l | xargs echo "  Total header files:"
echo "  Location: $PKG_INCLUDE_DIR/"
echo ""
echo "Libraries:"
echo "  $(basename "$LIB_FILE")"
echo "  libndsp_hifi5.a -> $(basename "$LIB_FILE") (symlink)"
echo "  Location: $PKG_LIB_DIR/"
echo "=========================================="
echo ""
echo "To use in your project:"
echo "  Include path: -I\$(NDSP_ROOT)/pkg/include"
echo "  Library path: -L\$(NDSP_ROOT)/pkg/lib -lndsp_hifi5"
echo ""
echo "✓ Build and export completed successfully!"
