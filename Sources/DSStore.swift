import Foundation

/// Reads and writes Finder's `.DS_Store` files: a buddy-allocated block file holding one B-tree of
/// records (file name, four-character code, typed value). Writing rebuilds the whole file from the
/// record list, laid out exactly as the widely used `ds_store` Python package lays out a new file,
/// and keeps the records in the order Finder stored them. Only call `write` while Finder is not
/// running: Finder keeps these files cached and rewrites them on its own.
struct DSStoreFile: Equatable {
    struct Record: Equatable {
        var name: String
        var code: String
        var type: String
        /// The encoded value exactly as it follows the type code in the file.
        var payload: Data
    }
    enum Failure: Error { case notDSStore, corrupt(String), unknownType(String) }

    var records: [Record] = []
    var headerExtra = Data([0, 0, 0x10, 0x0c, 0, 0, 0, 0x87, 0, 0, 0x20, 0x0b, 0, 0, 0, 0])

    init() {}

    // MARK: Values

    static func ustr(_ text: String) -> Data {
        let units = Array(text.utf16)
        var data = be32(UInt32(units.count))
        for unit in units { data.append(UInt8(unit >> 8)); data.append(UInt8(unit & 0xff)) }
        return data
    }
    static func long(_ value: UInt32) -> Data { be32(value) }
    static func blob(_ bytes: Data) -> Data { be32(UInt32(bytes.count)) + bytes }
    static func typeCode(_ code: String) -> Data { Data(code.utf8.prefix(4)) }

    func value(_ name: String, _ code: String) -> Record? { records.first { $0.name == name && $0.code == code } }
    func string(_ name: String, _ code: String) -> String? {
        guard let record = value(name, code), record.type == "ustr", record.payload.count >= 4 else { return nil }
        return Self.decodeUTF16(record.payload.subdata(in: 4..<record.payload.count))
    }
    func plist(_ name: String, _ code: String) -> [String: Any]? {
        guard let record = value(name, code), record.type == "blob", record.payload.count >= 4 else { return nil }
        return (try? PropertyListSerialization.propertyList(from: record.payload.subdata(in: 4..<record.payload.count), format: nil)) as? [String: Any]
    }

    /// Replaces the record for (name, code), or inserts it where Finder's ordering puts it: next
    /// to that name's other records, sorted by code, otherwise before the first larger name.
    mutating func set(_ name: String, _ code: String, type: String, payload: Data) {
        let record = Record(name: name, code: code, type: type, payload: payload)
        if let index = records.firstIndex(where: { $0.name == name && $0.code == code }) { records[index] = record; return }
        let key = Self.sortKey(name)
        let index = records.firstIndex { other in
            let otherKey = Self.sortKey(other.name)
            return otherKey.lexicographicallyPrecedes(key) == false && (otherKey != key || other.code > code)
        } ?? records.count
        records.insert(record, at: index)
    }

    /// The `ds_store` package's order: lower-cased name by code point, then code.
    static func sortKey(_ name: String) -> [UInt32] { name.lowercased().unicodeScalars.map(\.value) }

    // MARK: Reading

    init(data: Data) throws {
        let bytes = [UInt8](data)
        func u32(_ at: Int) throws -> UInt32 {
            guard at >= 0, at + 4 <= bytes.count else { throw Failure.corrupt("read past end") }
            return UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
        }
        // The allocator's offsets are relative to byte 4.
        guard bytes.count >= 36, try u32(0) == 1, Array(bytes[4..<8]) == Array("Bud1".utf8) else { throw Failure.notDSStore }
        let rootOffset = Int(try u32(8)), rootOffset2 = Int(try u32(16))
        guard rootOffset == rootOffset2 else { throw Failure.corrupt("root addresses differ") }
        headerExtra = Data(bytes[20..<36])
        var p = rootOffset + 4
        let count = Int(try u32(p)); p += 8
        guard count < 1_000_000 else { throw Failure.corrupt("block count") }
        var addresses: [UInt32] = []
        for i in 0..<count { addresses.append(try u32(p + 4 * i)) }
        p += 4 * ((count + 255) & ~255)
        let tocCount = Int(try u32(p)); p += 4
        var toc: [String: Int] = [:]
        for _ in 0..<tocCount {
            guard p < bytes.count else { throw Failure.corrupt("toc") }
            let length = Int(bytes[p]); p += 1
            guard p + length <= bytes.count else { throw Failure.corrupt("toc name") }
            let name = String(decoding: bytes[p..<p + length], as: UTF8.self); p += length
            toc[name] = Int(try u32(p)); p += 4
        }
        func block(_ id: Int) throws -> Int {
            guard id < addresses.count else { throw Failure.corrupt("block id") }
            return Int(addresses[id] & ~0x1f) + 4
        }
        guard let dsdb = toc["DSDB"] else { throw Failure.corrupt("no DSDB") }
        let superBlock = try block(dsdb)
        let rootNode = Int(try u32(superBlock))
        var visited = Set<Int>()
        var result: [Record] = []
        func readRecord(_ at: inout Int) throws -> Record {
            let nameLength = Int(try u32(at)); at += 4
            guard nameLength < 4096, at + 2 * nameLength + 8 <= bytes.count else { throw Failure.corrupt("name") }
            let name = Self.decodeUTF16(Data(bytes[at..<at + 2 * nameLength])); at += 2 * nameLength
            let code = String(decoding: bytes[at..<at + 4], as: UTF8.self)
            let type = String(decoding: bytes[at + 4..<at + 8], as: UTF8.self); at += 8
            let length: Int
            switch type {
            case "bool": length = 1
            case "long", "shor", "type": length = 4
            case "comp", "dutc": length = 8
            case "blob": length = 4 + Int(try u32(at))
            case "ustr": length = 4 + 2 * Int(try u32(at))
            default: throw Failure.unknownType(type)
            }
            guard length >= 0, at + length <= bytes.count else { throw Failure.corrupt("value") }
            let payload = Data(bytes[at..<at + length]); at += length
            return Record(name: name, code: code, type: type, payload: payload)
        }
        func traverse(_ node: Int, depth: Int) throws {
            guard depth < 32, visited.insert(node).inserted else { throw Failure.corrupt("tree loop") }
            var at = try block(node)
            let next = Int(try u32(at)), entries = Int(try u32(at + 4)); at += 8
            guard entries < 100_000 else { throw Failure.corrupt("entry count") }
            for _ in 0..<entries {
                if next != 0 { try traverse(Int(try u32(at)), depth: depth + 1); at += 4 }
                result.append(try readRecord(&at))
            }
            if next != 0 { try traverse(next, depth: depth + 1) }
        }
        try traverse(rootNode, depth: 0)
        records = result
    }

    // MARK: Writing

    func encoded() -> Data {
        var store = Buddy(headerExtra: headerExtra)
        let pageSize = 4096
        let superBlock = store.allocate(20, block: nil)
        store.toc["DSDB"] = UInt32(superBlock)
        if records.isEmpty {
            let root = store.allocate(pageSize, block: nil)
            store.write(block: root, Data(count: store.size(of: root)))
            store.write(block: superBlock, Self.be32(UInt32(root)) + Self.be32(0) + Self.be32(0) + Self.be32(1) + Self.be32(UInt32(pageSize)))
            return store.finish()
        }
        // Same bulk layout as ds_store's initial_entries: fill pages in order; the record that does
        // not fit a page moves up a level as the separator between two pages.
        var current = records, levels: [[[Record]]] = [], pointerSize = 0, nodeCount = 0
        while true {
            var nodes: [[Record]] = [], node: [Record] = [], next: [Record] = [], total = 8
            for record in current {
                let length = total + pointerSize + Self.length(of: record)
                if length > pageSize { nodes.append(node); next.append(record); total = 8; node = [] }
                else { total = length; node.append(record) }
            }
            if !node.isEmpty { nodes.append(node) }
            // A level needs one separator fewer than it has pages. When the last record was the one
            // pushed up, nothing follows it: it becomes a page of its own instead (ds_store drops it).
            else if next.count == nodes.count, nodes[nodes.count - 1].count > 1, let last = next.popLast() {
                next.append(nodes[nodes.count - 1].removeLast())
                nodes.append([last])
            }
            guard nodes.count == next.count + 1 || nodes.count == 1 else { preconditionFailure("DS_Store page layout") }
            nodeCount += nodes.count
            levels.append(nodes)
            if nodes.count == 1 { break }
            current = next; pointerSize = 4
        }
        var pointers = (0..<nodeCount).map { _ in store.allocate(pageSize, block: nil) }
        var previous: [Int]?
        for level in levels {
            var levelPointers = Array(pointers.suffix(level.count))
            pointers.removeLast(level.count)
            var made: [Int] = [], used = 0
            for node in level {
                let id = levelPointers.removeFirst()
                var data = Data()
                if let previous {
                    data += Self.be32(UInt32(previous[used + node.count])) + Self.be32(UInt32(node.count))
                    for (pointer, record) in zip(previous[used..<used + node.count], node) { data += Self.be32(UInt32(pointer)) + Self.encode(record) }
                } else {
                    data += Self.be32(0) + Self.be32(UInt32(node.count))
                    for record in node { data += Self.encode(record) }
                }
                store.write(block: id, data)
                made.append(id)
                // Each node owns its records' left children; the next pointer is the separator's
                // right child, which starts the following node.
                used += node.count + 1
            }
            previous = made
        }
        let root = previous![0]
        // Finder counts the levels above the leaves: a single page is level 0.
        store.write(block: superBlock, Self.be32(UInt32(root)) + Self.be32(UInt32(levels.count - 1)) + Self.be32(UInt32(records.count)) + Self.be32(UInt32(nodeCount)) + Self.be32(UInt32(pageSize)))
        return store.finish()
    }

    static func length(of record: Record) -> Int { 4 + 2 * record.name.utf16.count + 8 + record.payload.count }
    static func encode(_ record: Record) -> Data {
        var data = ustr(record.name)
        data += Data(record.code.utf8.prefix(4)) + Data(record.type.utf8.prefix(4))
        return data + record.payload
    }
    static func be32(_ value: UInt32) -> Data { Data([UInt8(value >> 24), UInt8(value >> 16 & 0xff), UInt8(value >> 8 & 0xff), UInt8(value & 0xff)]) }
    static func decodeUTF16(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        return String(decoding: units, as: UTF16.self)
    }

    static func == (a: Self, b: Self) -> Bool { a.records == b.records }
}

/// The buddy allocator of a new `.DS_Store` file, mirroring `ds_store`'s `Allocator.open("w+")`.
private struct Buddy {
    var offsets: [UInt32] = [2048 | 5]
    var free: [[UInt32]]
    var toc: [String: UInt32] = [:]
    var blocks: [Int: Data] = [:]
    let headerExtra: Data

    init(headerExtra: Data) {
        self.headerExtra = headerExtra
        free = (0..<32).map { width in (5...10).contains(width) || (12...30).contains(width) ? [UInt32(1) << UInt32(width)] : [] }
    }
    static func width(_ bytes: Int) -> Int { max(bytes == 0 ? 0 : Int.bitWidth - bytes.leadingZeroBitCount, 5) }
    func size(of block: Int) -> Int { 1 << Int(offsets[block] & 0x1f) }

    private mutating func release(_ offset: UInt32, _ width: Int) {
        var offset = offset, width = width
        while true {
            let buddy = offset ^ (UInt32(1) << UInt32(width))
            guard let index = free[width].firstIndex(of: buddy) else { break }
            offset &= buddy
            free[width].remove(at: index)
            width += 1
        }
        let at = free[width].firstIndex { $0 > offset } ?? free[width].count
        free[width].insert(offset, at: at)
    }
    private mutating func take(_ width: Int) -> UInt32 {
        var w = width
        while free[w].isEmpty { w += 1 }
        while w > width {
            let offset = free[w].removeFirst()
            w -= 1
            free[w] = [offset, offset ^ (UInt32(1) << UInt32(w))]
        }
        return free[width].removeFirst()
    }
    mutating func allocate(_ bytes: Int, block: Int?) -> Int {
        let block = block ?? (offsets.firstIndex(of: 0) ?? { offsets.append(0); return offsets.count - 1 }())
        let width = Self.width(bytes)
        let address = offsets[block]
        if address != 0 {
            if Int(address & 0x1f) == width { return block }
            release(address & ~0x1f, width)
            offsets[block] = 0
        }
        offsets[block] = take(width) | UInt32(width)
        return block
    }
    mutating func write(block: Int, _ data: Data) {
        var padded = data
        padded.append(Data(count: max(0, size(of: block) - data.count)))
        blocks[Int(offsets[block] & ~0x1f)] = padded
    }
    /// Writes the allocator's root block into block 0 and returns the whole file.
    mutating func finish() -> Data {
        let rootSize = 8 + 4 * ((offsets.count + 255) & ~255) + 4 + toc.keys.reduce(0) { $0 + 5 + $1.utf8.count } + free.reduce(0) { $0 + 4 + 4 * $1.count }
        _ = allocate(rootSize, block: 0)
        // Recomputed after the allocation, which may change the free lists.
        var root = DSStoreFile.be32(UInt32(offsets.count)) + DSStoreFile.be32(0)
        for offset in offsets { root += DSStoreFile.be32(offset) }
        if offsets.count & 255 != 0 { root += Data(count: 4 * (256 - offsets.count & 255)) }
        root += DSStoreFile.be32(UInt32(toc.count))
        for key in toc.keys.sorted() {
            root.append(UInt8(key.utf8.count)); root += Data(key.utf8); root += DSStoreFile.be32(toc[key]!)
        }
        for list in free {
            root += DSStoreFile.be32(UInt32(list.count))
            for offset in list { root += DSStoreFile.be32(offset) }
        }
        write(block: 0, root)
        let rootOffset = offsets[0] & ~0x1f
        var end = 2048
        for (offset, data) in blocks { end = max(end, offset + data.count) }
        var file = Data(count: 4 + end)
        let header = DSStoreFile.be32(1) + Data("Bud1".utf8) + DSStoreFile.be32(rootOffset) + DSStoreFile.be32(UInt32(size(of: 0))) + DSStoreFile.be32(rootOffset) + headerExtra
        file.replaceSubrange(0..<header.count, with: header)
        for (offset, data) in blocks { file.replaceSubrange(4 + offset..<4 + offset + data.count, with: data) }
        return file
    }
}
