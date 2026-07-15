---
name: swift-project-setup
description: Guides the creation of new Swift projects (CLI, iOS, macOS) and the setup of dependency managers (Swift Package Manager, CocoaPods) and XcodeGen. Use when starting a new Swift project, adding dependencies, configuring a project.yml, or generating Xcode projects.
---

# Swift Project Setup & Dependency Management

This guide covers modern workflows for creating Swift projects, managing dependencies with Swift Package Manager (SPM) and CocoaPods, and using XcodeGen to generate `.xcodeproj` files declaratively.

---

## 1. Creating a New Swift Project

Depending on the project type (command-line tool, library, or platform app), you can initialize the project using the Swift CLI or set up a clean directory structure for XcodeGen.

### Option A: Command-Line Tool or Library (Swift Package Manager)
To create a pure Swift project using the command-line interface, initialize it using the Swift build tool:

```sh
# Create a command-line executable
mkdir MyTool && cd MyTool
swift package init --type executable

# Create a reusable Swift library
mkdir MyLibrary && cd MyLibrary
swift package init --type library
```

This generates:
- `Package.swift`: The package manifest.
- `Sources/`: The source files directory.
- `Tests/`: Unit tests directory.

### Option B: Platform Application (iOS/macOS via XcodeGen)
When using XcodeGen, you don't need Xcode to create the initial project. Instead, create a directory layout on disk first, then define a `project.yml` file to generate the `.xcodeproj`.

#### How XcodeGen Maps Folders
Unlike traditional Xcode projects where you manage "Groups" manually, XcodeGen maps your physical folder structure directly to Xcode Groups:
- **Groups Match Folders**: If you have `Sources/Shared/Networking/NetworkClient.swift` on disk, it will appear in Xcode under the group path `Sources > Shared > Networking > NetworkClient.swift`.
- **Automatic File Additions**: Adding, renaming, or deleting a file in a folder on disk automatically updates the Xcode project upon the next `xcodegen generate` run.

#### Recommended Directory Structure (Feature-Based Layout)
A clean, modern directory structure for an iOS/macOS app using an MVVM or feature-oriented architecture:

```text
MyiOSApp/
├── project.yml                 # XcodeGen configuration
├── Makefile                    # Task automation (generation, build, test, clean)
├── .gitignore                  # Git ignore rules
├── Sources/                    # Main app target sources
│   ├── App/                    # App delegate, lifecycle, config
│   │   ├── MyiOSApp.swift      # SwiftUI App entry point (or AppDelegate.swift)
│   │   └── Info.plist          # App metadata settings
│   ├── Features/               # Organized by product features (scalable and modular)
│   │   ├── Home/
│   │   │   ├── Models/
│   │   │   ├── Views/
│   │   │   └── ViewModels/
│   │   └── Profile/
│   │       ├── Models/
│   │       ├── Views/
│   │       └── ViewModels/
│   ├── Shared/                 # Common components, utilities, network clients
│   │   ├── Extensions/
│   │   ├── UIComponents/       # Reusable buttons, cells, typography styles
│   │   └── Networking/
│   └── Resources/              # Asset catalogs, localization, files
│       ├── Assets.xcassets     # Colors, images, icons
│       └── Localizable.strings # String translations
├── Tests/                      # Unit & integration test sources
│   └── MyiOSAppTests.swift
└── UITests/                    # UI test sources (optional)
    └── MyiOSAppUITests.swift
```

#### Automating Folder Structure Creation (Bootstrap Command)
To bootstrap this directory structure instantly, run the following terminal command in your project root:

```sh
mkdir -p Sources/{App,Features/{Home/{Models,Views,ViewModels},Profile/{Models,Views,ViewModels}},Shared/{Extensions,UIComponents,Networking},Resources} Tests UITests
```

Or add it to your `Makefile` to make setup reproducible:

```makefile
# Create the standard folder structure on disk
bootstrap:
	mkdir -p Sources/{App,Features/{Home/{Models,Views,ViewModels},Profile/{Models,Views,ViewModels}},Shared/{Extensions,UIComponents,Networking},Resources} Tests UITests
	@echo "Directory structure bootstrapped successfully."
```

---

## 2. Dependency Management

Swift supports multiple dependency managers. Swift Package Manager is the native standard, while CocoaPods remains common in legacy or hybrid projects.

### Swift Package Manager (SPM)
SPM dependencies are declared in `Package.swift` or integrated directly into Xcode/XcodeGen.

#### Using `Package.swift` (For CLI/Library Packages)
Add the package to the `dependencies` array and link it to your target:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyTool",
    dependencies: [
        // Add external dependencies here
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MyTool",
            dependencies: [
                // Link the dependency to your target
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MyToolTests",
            dependencies: ["MyTool"]
        )
    ]
)
```

---

### CocoaPods
CocoaPods uses a `Podfile` to manage dependencies. It resolves dependencies and creates an `.xcworkspace` wrapping your project.

#### Standard `Podfile` Example
```ruby
platform :ios, '15.0'
use_frameworks!

target 'MyiOSApp' do
  # Add dependencies
  pod 'Alamofire', '~> 5.8.0'
  
  target 'MyiOSAppTests' do
    inherit! :search_paths
    pod 'Quick'
    pod 'Nimble'
  end
end
```

To install:
```sh
pod install
```
Always open the generated `.xcworkspace` file (not `.xcodeproj`) when using CocoaPods.

---

## 3. Using XcodeGen

XcodeGen is a command-line tool that generates your Xcode project file (`.xcodeproj`) from a folder structure and a YAML specification (`project.yml`).

### Why XcodeGen?
1. **No Git Merge Conflicts**: The `.xcodeproj` file is notorious for merge conflicts. XcodeGen generates this file dynamically, meaning you can git-ignore `.xcodeproj` and only track `project.yml`.
2. **Ease of Configuration**: Set compiler flags, build phases, and schemes in clean, readable YAML rather than clicking through Xcode UI menus.
3. **Consistent Builds**: Ensures all developers and CI pipelines use the exact same project structure.

### Installation
```sh
brew install xcodegen
```

### Writing the `project.yml` file
Create a `project.yml` file in the root of your project directory:

```yaml
name: MyiOSApp
options:
  bundleIdPrefix: com.example
targets:
  MyiOSApp:
    type: application
    platform: iOS
    deploymentTarget: "15.0"
    sources:
      - Sources
    settings:
      DEVELOPMENT_TEAM: "" # Add your Apple Team ID here
      INFOPLIST_FILE: Sources/Info.plist
    dependencies:
      # Native SPM dependency integration within XcodeGen
      - package: swift-argument-parser
        product: ArgumentParser

  MyiOSAppTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - Tests
    dependencies:
      - target: MyiOSApp

packages:
  swift-argument-parser:
    github: apple/swift-argument-parser
    from: 1.2.0
```

### Generating the Project
Run XcodeGen in the directory containing `project.yml`:

```sh
xcodegen generate
```

This reads the directories, source files, and dependencies, and writes a fully configured `MyiOSApp.xcodeproj` file to disk.

---

## 4. Combining XcodeGen with Dependency Managers

### SPM + XcodeGen (Recommended)
You can declare SPM packages directly in your `project.yml` under the `packages` section, and then reference them under a target's `dependencies`. When you run `xcodegen generate`, the Xcode project will be generated with Swift Packages resolved natively.

### CocoaPods + XcodeGen
If you need both, configure them in sequence:

1. **Write `project.yml`**: Declare targets and settings, but do not declare CocoaPods here.
2. **Write `Podfile`**: Define the targets matching those declared in `project.yml`.
3. **Build Script / Makefile**: Orchestrate the generation and installation sequence:

```makefile
# Run xcodegen first to build the project, then pod install to link pods
project:
	xcodegen generate
	pod install
```

Run `make project` whenever `project.yml` or the folder structure changes.

---

## 5. Best Practices & Git Hygiene

- **`.gitignore`**: Add `.xcodeproj` and `.xcworkspace` to your `.gitignore` file, keeping only `project.yml` under version control:
  ```text
  # XcodeGen / CocoaPods output
  *.xcodeproj
  *.xcworkspace
  Pods/
  ```
- **Source Folders**: Keep your files structured on disk. XcodeGen automatically maps subfolders to Xcode Groups.
- **CI Pipelines**: Run `xcodegen generate` (and `pod install` if applicable) as the very first step in your CI/CD configuration before compiling:
  ```yaml
  - name: Generate Xcode Project
    run: xcodegen generate
  ```
