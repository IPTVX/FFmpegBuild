// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AetherFFmpegBuild",
    platforms: [
        .iOS(.v16),
        .tvOS(.v16),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "AetherFFmpegBuild",
            targets: ["AetherFFmpegBuild"]
        ),
        // Individual libraries for consumers that want fine-grained control
        .library(name: "AetherLibavcodec", targets: ["AetherLibavcodec"]),
        .library(name: "AetherLibavformat", targets: ["AetherLibavformat"]),
        .library(name: "AetherLibavutil", targets: ["AetherLibavutil"]),
        .library(name: "AetherLibswresample", targets: ["AetherLibswresample"]),
        .library(name: "AetherLibswscale", targets: ["AetherLibswscale"]),
        .library(name: "AetherLibdav1d", targets: ["AetherLibdav1d"]),
        .library(name: "AetherLibavfilter", targets: ["AetherLibavfilter"]),
        .library(name: "AetherLibzimg", targets: ["AetherLibzimg"]),
        .library(name: "AetherLibzvbi", targets: ["AetherLibzvbi"]),
    ],
    targets: [
        // Umbrella target that links all FFmpeg libraries + dav1d + system frameworks
        .target(
            name: "AetherFFmpegBuild",
            dependencies: [
                "AetherLibavcodec",
                "AetherLibavformat",
                "AetherLibavutil",
                "AetherLibswresample",
                "AetherLibswscale",
                "AetherLibavfilter",
                "AetherLibdav1d",
                "AetherLibzimg",
                "AetherLibzvbi",
            ],
            path: "Sources/FFmpegBuild",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("VideoToolbox"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
                .linkedLibrary("c++"),
            ]
        ),
        // Prebuilt xcframeworks (created by build.sh)
        .binaryTarget(name: "AetherLibavcodec", path: "Sources/AetherLibavcodec.xcframework"),
        .binaryTarget(name: "AetherLibavformat", path: "Sources/AetherLibavformat.xcframework"),
        .binaryTarget(name: "AetherLibavutil", path: "Sources/AetherLibavutil.xcframework"),
        .binaryTarget(name: "AetherLibswresample", path: "Sources/AetherLibswresample.xcframework"),
        .binaryTarget(name: "AetherLibswscale", path: "Sources/AetherLibswscale.xcframework"),
        .binaryTarget(name: "AetherLibdav1d", path: "Sources/AetherLibdav1d.xcframework"),
        .binaryTarget(name: "AetherLibavfilter", path: "Sources/AetherLibavfilter.xcframework"),
        .binaryTarget(name: "AetherLibzimg", path: "Sources/AetherLibzimg.xcframework"),
        .binaryTarget(name: "AetherLibzvbi", path: "Sources/AetherLibzvbi.xcframework"),
        .testTarget(
            name: "FFmpegBuildTests",
            dependencies: ["AetherFFmpegBuild", "AetherLibavfilter", "AetherLibavutil"],
            path: "Tests/FFmpegBuildTests"
        ),
    ]
)
