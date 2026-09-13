#!/usr/bin/env python3
"""Cross-file symbol check.

Finds capitalized identifiers used in type position that are neither declared in this
project nor present in the SDK allowlist below. Without a Swift toolchain this is the
cheapest way to catch a renamed or misspelled type before opening Xcode.

    python3 Tools/symbolcheck.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE_DIRS = [os.path.join(ROOT, "Sources"), os.path.join(ROOT, "Tests")]

DECL = re.compile(r'\b(?:class|struct|enum|protocol|actor|typealias)\s+([A-Z][A-Za-z0-9_]*)')
# Type positions: `: Foo`, `-> Foo`, `Foo(`, `[Foo]`, `<Foo`, `is Foo`, `as Foo`
REF = re.compile(r'(?::\s*|->\s*|\bis\s+|\bas[?!]?\s+|\[|<|\()([A-Z][A-Za-z0-9_]*)')

ALLOWLIST = {
    # Swift standard library
    "Array", "Bool", "CaseIterable", "Character", "Codable", "CodingKey", "CodingKeys",
    "Comparable", "CustomStringConvertible", "Data", "Dictionary", "Double", "Encodable",
    "Decodable", "Decoder", "Encoder", "Equatable", "Error", "Float", "Hashable",
    "Identifiable", "Int", "Int8", "Int16", "Int32", "Int64", "OptionSet", "RawRepresentable",
    "Result", "Sendable", "Set", "String", "Task", "UInt", "UInt8", "UInt16", "UInt32",
    "UInt64", "Void", "ClosedRange", "Range", "Optional", "Sequence", "Collection",
    "RandomNumberGenerator", "SystemRandomNumberGenerator", "AnyObject", "Any",
    "MainActor", "Never", "Self", "UnicodeScalar", "Mirror", "ObjectIdentifier",
    # Foundation
    "Bundle", "Calendar", "Date", "DateFormatter", "FileManager", "JSONDecoder",
    "JSONEncoder", "LocalizedError", "NSLock", "Notification", "NumberFormatter",
    "ProcessInfo", "TimeInterval", "URL", "URLRequest", "URLSession",
    "URLSessionConfiguration", "URLSessionWebSocketTask", "URLSessionWebSocketDelegate",
    "UUID", "NSRange", "NSTemporaryDirectory", "utsname",
    # Combine / SwiftUI
    "AnyCancellable", "AnyView", "App", "Binding", "Button", "ButtonStyle", "Canvas",
    "Capsule", "Circle", "Color", "ColorScheme", "Content", "Divider", "EnvironmentObject",
    "Font", "ForEach", "GeometryReader", "GridItem", "Group", "HStack", "Image",
    "LazyVGrid", "LinearGradient", "Link", "Menu", "ObservableObject", "ObservedObject",
    "Path", "Picker", "ProgressView", "RadialGradient", "Rectangle", "RoundedRectangle",
    "ScrollView", "Scene", "ShapeStyle", "Slider", "Spacer", "State", "StateObject",
    "StrokeStyle", "Text", "TextField", "Toggle", "VStack", "View", "ViewBuilder",
    "ViewModifier", "WindowGroup", "ZStack", "DragGesture", "Environment", "Published",
    "CGFloat", "CGPoint", "CGRect", "CGSize", "CGVector", "CGContext", "CGGradient",
    "CGColorSpaceCreateDeviceRGB", "Angle", "UnitPoint", "Animation", "Transaction",
    # UIKit / CoreGraphics
    "UIApplication", "UIColor", "UIFont", "UIGraphicsImageRenderer", "UIImage",
    "UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator",
    "UISelectionFeedbackGenerator", "UIScreen", "UIView", "UIViewController",
    "UIViewRepresentable", "UIWindowScene", "Context",
    # SceneKit
    "SCNAction", "SCNBillboardConstraint", "SCNBox", "SCNCamera", "SCNCone", "SCNCylinder",
    "SCNGeometry", "SCNLight", "SCNMaterial", "SCNMatrix4MakeScale",
    "SCNMatrix4MakeTranslation", "SCNNode", "SCNParticleSystem", "SCNPhysicsBody",
    "SCNPhysicsShape", "SCNPlane", "SCNScene", "SCNSceneRenderer",
    "SCNSceneRendererDelegate", "SCNSphere", "SCNText", "SCNTube", "SCNVector3",
    "SCNVector4", "SCNVector3Zero", "SCNView",
    # AVFoundation
    "AVAudio3DPoint", "AVAudio3DVector", "AVAudio3DVectorOrientation", "AVAudioEngine",
    "AVAudioEnvironmentNode", "AVAudioFile", "AVAudioFormat", "AVAudioFrameCount",
    "AVAudioMixerNode", "AVAudioPCMBuffer", "AVAudioPlayerNode", "AVAudioSession",
    # StoreKit / GameKit / Network / CoreHaptics / Metal
    "AppStore", "Product", "VerificationResult", "GKAchievement", "GKGameCenterViewController",
    "GKGameCenterControllerDelegate", "GKLeaderboard", "GKLocalPlayer", "NWBrowser",
    "NWConnection", "NWListener", "NWParameters", "NWProtocolIP", "CHHapticEngine",
    "CHHapticEvent", "CHHapticEventParameter", "CHHapticPattern", "CHHapticTimeImmediate",
    "MTLCreateSystemDefaultDevice", "DispatchQueue",
    # XCTest
    "XCTestCase", "XCTAssert", "XCTAssertEqual", "XCTAssertNotNil", "XCTFail",
    # Generic parameters, associated types and enclosing-scope names that the regex sees
    # in type position but that are never declarations.
    "Bound", "Element", "T", "Configuration", "Content", "IDs", "Swift",
    "CFArray", "CFData", "CGBitmapInfo", "CGImage", "CGImageAlphaInfo", "CGDataProvider",
    "CheckedContinuation", "NSObject", "NSNumber", "NSString", "NSAttributedString",
    "UTF8", "WritableKeyPath", "utsname", "ByteCountFormatter",
    # Seen inside string interpolation, which the stripper deliberately does not parse.
    "GemsCredits", "Foundation",
}

def strip_noise(text):
    out, i, n = [], 0, len(text)
    while i < n:
        if text[i] == '"':
            if text[i:i + 3] == '"""':
                end = text.find('"""', i + 3)
                i = n if end == -1 else end + 3
                continue
            i += 1
            while i < n:
                if text[i] == '\\':
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            continue
        if text[i:i + 2] == '//':
            end = text.find('\n', i)
            i = n if end == -1 else end
            continue
        if text[i:i + 2] == '/*':
            depth, i = 1, i + 2
            while i < n and depth:
                if text[i:i + 2] == '/*':
                    depth += 1; i += 2
                elif text[i:i + 2] == '*/':
                    depth -= 1; i += 2
                else:
                    i += 1
            continue
        out.append(text[i]); i += 1
    return ''.join(out)

def main():
    declared, references = set(), {}
    for base in SOURCE_DIRS:
        for dirpath, _, filenames in os.walk(base):
            for name in sorted(filenames):
                if not name.endswith('.swift'):
                    continue
                path = os.path.join(dirpath, name)
                code = strip_noise(open(path, encoding='utf-8').read())
                declared.update(DECL.findall(code))
                rel = os.path.relpath(path, ROOT)
                for match in REF.finditer(code):
                    references.setdefault(match.group(1), set()).add(rel)

    unknown = {name: files for name, files in references.items()
               if name not in declared and name not in ALLOWLIST}
    print(f"{len(declared)} types declared, {len(references)} referenced")
    if unknown:
        print("unresolved type references (add to the allowlist if they are SDK symbols):")
        for name in sorted(unknown):
            print(f"  {name}: {', '.join(sorted(unknown[name])[:3])}")
        return 1
    print("OK")
    return 0

if __name__ == '__main__':
    sys.exit(main())
