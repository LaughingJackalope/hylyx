import Foundation
import Darwin

enum ImageService {
    enum Source {
        case local(URL)
        case cloud(String)
    }
    
    private static let imagesURL = Defaults.cloudURL.appendingPathComponent("images")

    // MARK: - Resolve

    static func resolve(from source: Source, into dir: URL) throws -> URL {
        switch source {
        case .local(let path):
            guard FileManager.default.fileExists(atPath: path.path) else {
                throw HyError.notFound(path.path)
            }
            let dst = dir.appendingPathComponent(path.lastPathComponent)
            try? FileManager.default.removeItem(at: dst)
            try FileManager.default.copyItem(at: path, to: dst)
            return dst

        case .cloud(let base):
            try Validation.imageName(base)
            let hasExt = base.hasSuffix(".tar.xz") || base.hasSuffix(".tar.zst") || base.hasSuffix(".tar.zstd")
            let fileName = hasExt ? base : try latestVersion(for: base)
            let url = imagesURL.appendingPathComponent(fileName)
            let dst = dir.appendingPathComponent(fileName)
            Log.step("Downloading \(fileName)...")
            try download(from: url, to: dst)
            return dst
        }
    }

    // MARK: - Download

    private static let processLock = NSLock()
    private static var currentProcess: Process?
    private static var signalSource: DispatchSourceSignal?

    static func download(from url: URL, to dst: URL) throws {
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-L", "--connect-timeout", "10", "--speed-limit", "1000", "--speed-time", "30", "--progress-bar", "-o", dst.path, url.absoluteString]
        curl.standardOutput = FileHandle.standardError

        // Handle Ctrl+C safely via GCD with proper synchronization
        processLock.lock()
        currentProcess = curl
        processLock.unlock()

        signal(SIGINT, SIG_IGN)
        signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signalSource?.setEventHandler {
            processLock.lock()
            let proc = currentProcess
            processLock.unlock()
            proc?.terminate()
            print("\n")
            exit(130)
        }
        signalSource?.resume()

        defer {
            signalSource?.cancel()
            signalSource = nil
            signal(SIGINT, SIG_DFL)
            processLock.lock()
            currentProcess = nil
            processLock.unlock()
        }

        try curl.run()
        curl.waitUntilExit()

        guard curl.terminationStatus == 0 else {
            throw HyError.executionFailed(command: "curl", exitCode: curl.terminationStatus)
        }
    }

    // MARK: - Extract

    static func extract(archive: URL, to dir: URL) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xf", archive.path, "-C", dir.path]
        tar.standardError = FileHandle.nullDevice
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            throw HyError.extractionFailed(archive.lastPathComponent)
        }
    }

    // MARK: - Index

    static func fetchIndex() throws -> String {
        let pipe = Pipe()
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        curl.arguments = ["-Ls", "--connect-timeout", "10", "--max-time", "30", imagesURL.absoluteString]
        curl.standardOutput = pipe
        try curl.run(); curl.waitUntilExit()
        guard curl.terminationStatus == 0 else {
            throw HyError.executionFailed(command: "curl", exitCode: curl.terminationStatus)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let html = String(data: data, encoding: .utf8) else {
            throw HyError.extractionFailed("index decode")
        }
        return html
    }

    static func latestVersion(for base: String) throws -> String {
        let html = try fetchIndex()
        let pattern = "<span class=\"name\">(\(base)-[0-9.][\\w.-]*?\\.tar\\.(?:xz|zst|zstd))</span>"
        let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        let best = matches.compactMap { m -> (String, [Int])? in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            let fname = String(html[r])
            let vStr = fname
                .replacingOccurrences(of: "\(base)-", with: "")
                .replacingOccurrences(of: ".tar.xz", with: "")
                .replacingOccurrences(of: ".tar.zst", with: "")
                .replacingOccurrences(of: ".tar.zstd", with: "")
            let nums = vStr.split(separator: ".").compactMap { Int($0) }
            return (fname, nums)
        }.max { $0.1.lexicographicallyPrecedes($1.1) }

        guard let name = best?.0 else {
            throw HyError.notFound("\(base) (cloud)")
        }
        return name
    }

    static func firstFile(in dir: URL) -> URL? {
        guard let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in en {
            return url
        }
        return nil
    }
}
