#!/bin/zsh
#
# Repackages the prebuilt FFmpegBuild 2.4.3 XCFrameworks with Aether-specific
# framework and Clang module identities. The compiled FFmpeg code is unchanged.
#
# Failure modes:
# - A source XCFramework is missing or already partially transformed.
# - A framework slice has an unexpected shallow/deep bundle layout.
# - A Mach-O dependency still points at an unnamespaced sibling framework.
# - A transformed bundle cannot be ad-hoc signed after metadata changes.

set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly SOURCES_DIR="${SCRIPT_DIR}/Sources"
readonly STAGING_DIR="${SCRIPT_DIR}/build/namespaced"
readonly PAIRS=(
    "Libavcodec:AetherLibavcodec"
    "Libavformat:AetherLibavformat"
    "Libavutil:AetherLibavutil"
    "Libswresample:AetherLibswresample"
    "Libswscale:AetherLibswscale"
    "Libavfilter:AetherLibavfilter"
    "Libdav1d:AetherLibdav1d"
    "Libzimg:AetherLibzimg"
    "Libzvbi:AetherLibzvbi"
)

require_tool() {
    local TOOL="$1"

    if ! command -v "${TOOL}" >/dev/null 2>&1; then
        echo "ERROR: required tool not found: ${TOOL}"
        exit 1
    fi
}

namespaced_dependency() {
    local DEPENDENCY="$1"
    local PAIR OLD_NAME NEW_NAME

    for PAIR in "${PAIRS[@]}"; do
        OLD_NAME="${PAIR%%:*}"
        NEW_NAME="${PAIR##*:}"
        if [[ "${DEPENDENCY}" == *"/${OLD_NAME}.framework/"* ]]; then
            echo "${DEPENDENCY//${OLD_NAME}/${NEW_NAME}}"
            return
        fi
    done

    echo "${DEPENDENCY}"
}

rewrite_binary() {
    local BINARY="$1"
    local NEW_NAME="$2"
    local IS_MACOS="$3"
    local INSTALL_PATH="@rpath/${NEW_NAME}.framework/${NEW_NAME}"
    local DEPENDENCY NEW_DEPENDENCY

    if [[ "${IS_MACOS}" == "true" ]]; then
        INSTALL_PATH="@rpath/${NEW_NAME}.framework/Versions/A/${NEW_NAME}"
    fi

    install_name_tool -id "${INSTALL_PATH}" "${BINARY}"

    while IFS= read -r DEPENDENCY; do
        NEW_DEPENDENCY="$(namespaced_dependency "${DEPENDENCY}")"
        if [[ "${NEW_DEPENDENCY}" != "${DEPENDENCY}" ]]; then
            install_name_tool -change "${DEPENDENCY}" "${NEW_DEPENDENCY}" "${BINARY}"
        fi
    done < <(otool -L "${BINARY}" | awk 'NR > 1 { print $1 }')
}

rewrite_header_imports() {
    local FRAMEWORK="$1"
    local HEADER

    while IFS= read -r HEADER; do
        perl -pi -e '
            s#([<"])libavcodec/#${1}AetherLibavcodec/#g;
            s#([<"])libavformat/#${1}AetherLibavformat/#g;
            s#([<"])libavutil/#${1}AetherLibavutil/#g;
            s#([<"])libswresample/#${1}AetherLibswresample/#g;
            s#([<"])libswscale/#${1}AetherLibswscale/#g;
            s#([<"])libavfilter/#${1}AetherLibavfilter/#g;
        ' "${HEADER}"
    done < <(find "${FRAMEWORK}" -path '*/Headers/*' -type f -name '*.h')
}

rewrite_framework() {
    local OLD_FRAMEWORK="$1"
    local OLD_NAME="$2"
    local NEW_NAME="$3"
    local NEW_FRAMEWORK="${OLD_FRAMEWORK:h}/${NEW_NAME}.framework"
    local BINARY IS_MACOS="false" MODULE_MAP INFO_PLIST

    find "${OLD_FRAMEWORK}" -type d -name _CodeSignature -prune -exec rm -rf {} +

    if [[ -f "${OLD_FRAMEWORK}/Versions/A/${OLD_NAME}" ]]; then
        IS_MACOS="true"
        mv "${OLD_FRAMEWORK}/Versions/A/${OLD_NAME}" "${OLD_FRAMEWORK}/Versions/A/${NEW_NAME}"
        rm "${OLD_FRAMEWORK}/${OLD_NAME}"
        ln -s "Versions/Current/${NEW_NAME}" "${OLD_FRAMEWORK}/${NEW_NAME}"
        BINARY="${OLD_FRAMEWORK}/Versions/A/${NEW_NAME}"
    elif [[ -f "${OLD_FRAMEWORK}/${OLD_NAME}" ]]; then
        mv "${OLD_FRAMEWORK}/${OLD_NAME}" "${OLD_FRAMEWORK}/${NEW_NAME}"
        BINARY="${OLD_FRAMEWORK}/${NEW_NAME}"
    else
        echo "ERROR: unsupported framework layout: ${OLD_FRAMEWORK}"
        exit 1
    fi

    while IFS= read -r MODULE_MAP; do
        perl -pi -e "s/framework module ${OLD_NAME} /framework module ${NEW_NAME} /g" "${MODULE_MAP}"
    done < <(find "${OLD_FRAMEWORK}" -name module.modulemap -type f)

    while IFS= read -r INFO_PLIST; do
        /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${NEW_NAME}" "${INFO_PLIST}"
        /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.iptvx.aetherengine.${NEW_NAME}" "${INFO_PLIST}"
        /usr/libexec/PlistBuddy -c "Set :CFBundleName ${NEW_NAME}" "${INFO_PLIST}"
        plutil -lint "${INFO_PLIST}" >/dev/null
    done < <(find "${OLD_FRAMEWORK}" -name Info.plist -type f)

    rewrite_header_imports "${OLD_FRAMEWORK}"
    rewrite_binary "${BINARY}" "${NEW_NAME}" "${IS_MACOS}"
    mv "${OLD_FRAMEWORK}" "${NEW_FRAMEWORK}"
    codesign --force --sign - "${NEW_FRAMEWORK}"
}

rewrite_xcframework() {
    local OLD_NAME="$1"
    local NEW_NAME="$2"
    local OLD_XCFRAMEWORK="${SOURCES_DIR}/${OLD_NAME}.xcframework"
    local NEW_XCFRAMEWORK="${STAGING_DIR}/${NEW_NAME}.xcframework"
    local FRAMEWORK ROOT_PLIST

    if [[ ! -d "${OLD_XCFRAMEWORK}" ]]; then
        echo "ERROR: source XCFramework not found: ${OLD_XCFRAMEWORK}"
        exit 1
    fi

    cp -R "${OLD_XCFRAMEWORK}" "${NEW_XCFRAMEWORK}"

    while IFS= read -r FRAMEWORK; do
        rewrite_framework "${FRAMEWORK}" "${OLD_NAME}" "${NEW_NAME}"
    done < <(find "${NEW_XCFRAMEWORK}" -type d -name "${OLD_NAME}.framework")

    ROOT_PLIST="${NEW_XCFRAMEWORK}/Info.plist"
    perl -pi -e "s/${OLD_NAME}/${NEW_NAME}/g" "${ROOT_PLIST}"
    plutil -lint "${ROOT_PLIST}" >/dev/null
}

verify_namespaces() {
    local PAIR OLD_NAME NEW_NAME XCFRAMEWORK FRAMEWORK BINARY DEPENDENCY
    local CHECK_PAIR CHECK_OLD_NAME

    for PAIR in "${PAIRS[@]}"; do
        OLD_NAME="${PAIR%%:*}"
        NEW_NAME="${PAIR##*:}"
        XCFRAMEWORK="${SOURCES_DIR}/${NEW_NAME}.xcframework"

        if [[ ! -d "${XCFRAMEWORK}" ]]; then
            echo "ERROR: transformed XCFramework not found: ${XCFRAMEWORK}"
            exit 1
        fi

        for CHECK_PAIR in "${PAIRS[@]}"; do
            CHECK_OLD_NAME="${CHECK_PAIR%%:*}"
            if find "${XCFRAMEWORK}" \( -name Info.plist -o -name module.modulemap \) -type f -exec grep -El "(^|[^[:alnum:]_])${CHECK_OLD_NAME}([^[:alnum:]_]|$)" {} + | grep -q .; then
                echo "ERROR: stale ${CHECK_OLD_NAME} metadata found in ${XCFRAMEWORK}"
                exit 1
            fi
        done

        if find "${XCFRAMEWORK}" -path '*/Headers/*' -type f -name '*.h' -exec grep -El '^[[:space:]]*#[[:space:]]*include[[:space:]]*[<"]lib(avcodec|avformat|avutil|swresample|swscale|avfilter)/' {} + | grep -q .; then
            echo "ERROR: stale FFmpeg framework header import found in ${XCFRAMEWORK}"
            exit 1
        fi

        while IFS= read -r FRAMEWORK; do
            codesign --verify --strict "${FRAMEWORK}"
        done < <(find "${XCFRAMEWORK}" -type d -name "${NEW_NAME}.framework")

        while IFS= read -r BINARY; do
            while IFS= read -r DEPENDENCY; do
                for CHECK_PAIR in "${PAIRS[@]}"; do
                    CHECK_OLD_NAME="${CHECK_PAIR%%:*}"
                    if [[ "${DEPENDENCY}" == *"/${CHECK_OLD_NAME}.framework/"* ]]; then
                        echo "ERROR: stale dependency ${DEPENDENCY} found in ${BINARY}"
                        exit 1
                    fi
                done
            done < <(otool -L "${BINARY}" | awk 'NR > 1 { print $1 }')
        done < <(find "${XCFRAMEWORK}" -type f -name "${NEW_NAME}")
    done
}

require_tool install_name_tool
require_tool otool
require_tool codesign
require_tool plutil

ALREADY_NAMESPACED="true"
for PAIR in "${PAIRS[@]}"; do
    if [[ -d "${SOURCES_DIR}/${PAIR%%:*}.xcframework" || ! -d "${SOURCES_DIR}/${PAIR##*:}.xcframework" ]]; then
        ALREADY_NAMESPACED="false"
        break
    fi
done

if [[ "${ALREADY_NAMESPACED}" == "true" ]]; then
    verify_namespaces
    echo "Namespaced FFmpeg XCFrameworks already verified."
    exit 0
fi

rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

for PAIR in "${PAIRS[@]}"; do
    rewrite_xcframework "${PAIR%%:*}" "${PAIR##*:}"
done

for PAIR in "${PAIRS[@]}"; do
    rm -rf "${SOURCES_DIR}/${PAIR%%:*}.xcframework"
    mv "${STAGING_DIR}/${PAIR##*:}.xcframework" "${SOURCES_DIR}/"
done

verify_namespaces
rm -rf "${STAGING_DIR}"

echo "Namespaced FFmpeg XCFrameworks created successfully."
