//
//  ScanService.swift
//  IconFinder
//
//  Provides asynchronous image scanning using mdfind (fast) or find (deep),
//  emitting batched file path results back to Objective-C via block callbacks.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

@objcMembers
@objc(ScannedItem)
public final class ScannedItem: NSObject {
    public let path: String
    public let uti: String?
    public let size: NSNumber?
    public let modDate: NSDate?
    public dynamic var sha256: String?

    public init(path: String, uti: String?, size: NSNumber?, modDate: NSDate?) {
        self.path = path
        self.uti = uti
        self.size = size
        self.modDate = modDate
        self.sha256 = nil
        super.init()
    }
}

@objcMembers
@objc(ScanService)
public final class ScanService: NSObject {
    public typealias BatchHandler = ([ScannedItem]) -> Void
    public typealias FinishHandler = () -> Void

    @objc public static let shared = ScanService()

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var buffer = Data()
    private let queue = DispatchQueue(label: "scan.service.queue", qos: .userInitiated)
    private(set) dynamic var running: Bool = false
    private var deniedPrefixes: [String] = []
    private var isDeepScan: Bool = false

    private let imageExtensions: Set<String> = ["jpeg","jpg","gif","png","icns","tiff","pdf"]

    @objc public func startScan(_ deepScan: Bool,
                   allowedRoots: [String],
                   deniedRoots: [String],
                   includeExternalVolumes: Bool,
                   onBatch: @escaping BatchHandler,
                   onFinish: @escaping FinishHandler) {
        stop() // ensure any previous run is canceled

        queue.async { [weak self] in
            guard let self = self else { return }

            let proc = Process()
            let pipe = Pipe()
            proc.standardOutput = pipe

            self.isDeepScan = deepScan
            // Build denied prefixes; also exclude /Volumes when toggle is OFF in either mode
            var denied = deniedRoots
            if includeExternalVolumes == false {
                denied.append("/Volumes")
            }
            self.deniedPrefixes = denied
            if deepScan {
                proc.launchPath = "/usr/bin/find"
                var args: [String] = []
                // Roots to search
                args.append(contentsOf: allowedRoots)
                // Prune denied directories (if any)
                if !denied.isEmpty {
                    args.append(contentsOf: ["-type","d","("])
                    for (idx, path) in denied.enumerated() {
                        args.append(contentsOf: ["-path", path])
                        if idx < denied.count - 1 { args.append("-o") }
                    }
                    args.append(contentsOf: [")","-prune","-o"])
                }
                // File type and name filters
                args.append(contentsOf: ["-type","f","(",
                                         "-iname","*.icns","-o",
                                         "-iname","*.png","-o",
                                         "-iname","*.tiff","-o",
                                         "-iname","*.gif","-o",
                                         "-iname","*.jpg","-o",
                                         "-iname","*.jpeg","-o",
                                         "-iname","*.pdf",")","-print"])
                proc.arguments = args
            } else {
                proc.launchPath = "/usr/bin/mdfind"
                let query = "(kMDItemContentTypeTree == \"public.image\" || kMDItemContentType == \"com.apple.icns\" || kMDItemContentType == \"public.pdf\" || kMDItemContentTypeTree == \"com.adobe.pdf\")"
                var args: [String] = []
                for root in allowedRoots { args.append(contentsOf: ["-onlyin", root]) }
                if includeExternalVolumes { args.append(contentsOf: ["-onlyin", "/Volumes"]) }
                args.append(query)
                proc.arguments = args
            }

            self.process = proc
            self.stdoutPipe = pipe
            self.buffer.removeAll(keepingCapacity: false)

            // Setup stream handler
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self = self else { return }
                let data = handle.availableData
                if data.count == 0 { return } // EOF handled by termination handler
                self.buffer.append(data)
                self.flushLinesIfPossible(onBatch: onBatch)
            }

            // Termination
            proc.terminationHandler = { [weak self] _ in
                guard let self = self else { return }
                // Flush remainder
                self.flushRemaining(onBatch: onBatch)
                self.running = false
                DispatchQueue.main.async { onFinish() }
            }

            do {
                try proc.run()
                self.running = true
            } catch {
                self.running = false
                DispatchQueue.main.async { onFinish() }
            }
        }
    }

    @objc public func stop() {
        queue.sync {
            self.process?.terminate()
            self.process = nil
            self.stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            self.stdoutPipe = nil
            self.buffer.removeAll(keepingCapacity: false)
            self.running = false
        }
    }

    private func flushLinesIfPossible(onBatch: @escaping BatchHandler) {
        // Split on newlines; keep the trailing partial line in buffer
        var lines: [String] = []
        buffer.withUnsafeBytes { rawBuf in
            _ = rawBuf.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer<UInt8>(bitPattern: 0)
            var start = 0
            for i in 0..<buffer.count {
                if buffer[i] == 0x0A { // '\n'
                    let lineData = buffer.subdata(in: start..<i)
                    if let s = String(data: lineData, encoding: .utf8), !s.isEmpty { lines.append(s) }
                    start = i + 1
                }
            }
            if start > 0 {
                buffer.removeSubrange(0..<start)
            }
        }
        if lines.isEmpty { return }
        // Filter to known image extensions to reduce noise (deepScan already filters)
        var filtered = lines.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }
        // In fast mode, exclude denied roots manually since mdfind lacks an exclude switch
        if !isDeepScan && !deniedPrefixes.isEmpty {
            filtered = filtered.filter { path in
                for denied in deniedPrefixes {
                    if path.hasPrefix(denied) { return false }
                }
                return true
            }
        }
        if filtered.isEmpty { return }
        let items = self.buildItems(from: filtered)
        guard !items.isEmpty else { return }
        DispatchQueue.main.async { onBatch(items) }
    }

    private func flushRemaining(onBatch: @escaping BatchHandler) {
        guard !buffer.isEmpty else { return }
        let tail = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll(keepingCapacity: false)
        let lines = tail.split(separator: "\n").map(String.init)
        var filtered = lines.filter { path in
            let ext = (path as NSString).pathExtension.lowercased()
            return imageExtensions.contains(ext)
        }
        if !isDeepScan && !deniedPrefixes.isEmpty {
            filtered = filtered.filter { path in
                for denied in deniedPrefixes {
                    if path.hasPrefix(denied) { return false }
                }
                return true
            }
        }
        if !filtered.isEmpty {
            let items = self.buildItems(from: filtered)
            guard !items.isEmpty else { return }
            DispatchQueue.main.async { onBatch(items) }
        }
    }

    private func buildItems(from paths: [String]) -> [ScannedItem] {
        var result: [ScannedItem] = []
        result.reserveCapacity(paths.count)
        for path in paths {
            let url = URL(fileURLWithPath: path)
            do {
                let rv = try url.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .contentModificationDateKey])
                let uti = rv.contentType?.identifier
                let sizeNum: NSNumber? = (rv.fileSize != nil) ? NSNumber(value: rv.fileSize!) : nil
                let mod: NSDate? = (rv.contentModificationDate != nil) ? rv.contentModificationDate! as NSDate : nil
                result.append(ScannedItem(path: path, uti: uti, size: sizeNum, modDate: mod))
            } catch {
                // If resourceValues fail (e.g., permission), still include at least the path
                result.append(ScannedItem(path: path, uti: nil, size: nil, modDate: nil))
            }
        }
        return result
    }
}

