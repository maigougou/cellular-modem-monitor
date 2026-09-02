import Darwin
import Foundation
import SystemConfiguration

/// A small, value-semantic IPv4 representation used by discovery. Keeping it
/// independent of Network.framework makes topology generation deterministic in
/// unit tests and avoids accepting malformed dotted-decimal input.
struct IPv4HostAddress: Hashable, Comparable, Sendable, CustomStringConvertible {
    let rawValue: UInt32

    init?(string: String) {
        let components = string.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return nil }

        var value: UInt32 = 0
        for component in components {
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber),
                  let octet = UInt8(component)
            else { return nil }
            value = (value << 8) | UInt32(octet)
        }
        rawValue = value
    }

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    var description: String {
        [24, 16, 8, 0]
            .map { String((rawValue >> UInt32($0)) & 0xff) }
            .joined(separator: ".")
    }

    var isLoopback: Bool { rawValue >> 24 == 127 }

    var isLinkLocal: Bool { rawValue >> 16 == 0xa9fe }

    var isPrivate: Bool {
        let first = rawValue >> 24
        let firstTwo = rawValue >> 16
        return first == 10 ||
            firstTwo == 0xc0a8 ||
            (0xac10...0xac1f).contains(firstTwo)
    }

    static func < (lhs: IPv4HostAddress, rhs: IPv4HostAddress) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct IPv4InterfaceAddress: Hashable, Sendable {
    let address: IPv4HostAddress
    let prefixLength: UInt8

    init(address: IPv4HostAddress, prefixLength: UInt8) {
        self.address = address
        self.prefixLength = min(prefixLength, 32)
    }

    func contains(_ candidate: IPv4HostAddress) -> Bool {
        guard prefixLength > 0 else { return true }
        let mask = UInt32.max << UInt32(32 - prefixLength)
        return address.rawValue & mask == candidate.rawValue & mask
    }
}

enum NetworkInterfaceKind: String, Hashable, Sendable {
    case physical
    case loopback
    case tunnel
    case peerToPeer
}

struct NetworkInterfaceSnapshot: Hashable, Sendable {
    let name: String
    let index: UInt32
    let serviceID: String?
    let kind: NetworkInterfaceKind
    let isUp: Bool
    let isRunning: Bool
    let isPrimary: Bool
    let addresses: [IPv4InterfaceAddress]
    let router: IPv4HostAddress?
    let allAddresses: [String]

    init(
        name: String,
        index: UInt32,
        serviceID: String?,
        kind: NetworkInterfaceKind,
        isUp: Bool,
        isRunning: Bool,
        isPrimary: Bool,
        addresses: [IPv4InterfaceAddress],
        router: IPv4HostAddress?,
        allAddresses: [String]? = nil
    ) {
        self.name = name
        self.index = index
        self.serviceID = serviceID
        self.kind = kind
        self.isUp = isUp
        self.isRunning = isRunning
        self.isPrimary = isPrimary
        self.addresses = addresses
        self.router = router
        self.allAddresses = allAddresses ?? addresses.map(\.address.description)
    }

    var isEligibleForModemDiscovery: Bool {
        isUp && isRunning && kind == .physical && !addresses.isEmpty
    }
}

struct NetworkTopologySnapshot: Equatable, Sendable {
    let interfaces: [NetworkInterfaceSnapshot]
    let primaryIPv4InterfaceName: String?
    let primaryIPv6InterfaceName: String?

    init(
        interfaces: [NetworkInterfaceSnapshot],
        primaryIPv4InterfaceName: String? = nil,
        primaryIPv6InterfaceName: String? = nil
    ) {
        self.interfaces = interfaces
        self.primaryIPv4InterfaceName = primaryIPv4InterfaceName
        self.primaryIPv6InterfaceName = primaryIPv6InterfaceName
    }

    static let empty = NetworkTopologySnapshot(interfaces: [])

    var discoveryInterfaces: [NetworkInterfaceSnapshot] {
        interfaces.filter(\.isEligibleForModemDiscovery)
    }
}

protocol NetworkTopologyProviding: Sendable {
    func snapshot() -> NetworkTopologySnapshot
}

/// Reads current interface/link state with getifaddrs and enriches it with the
/// per-service router and primary-interface state published by configd. It does
/// not invoke route, networksetup, scutil, or any other subprocess.
struct SystemNetworkTopologyProvider: NetworkTopologyProviding {
    func snapshot() -> NetworkTopologySnapshot {
        let serviceState = Self.copyIPv4ServiceState()
        let primaryIPv4Interface = Self.copyPrimaryInterfaceName(entity: kSCEntNetIPv4)
        let primaryIPv6Interface = Self.copyPrimaryInterfaceName(entity: kSCEntNetIPv6)
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else {
            return .empty
        }
        defer { freeifaddrs(pointer) }

        struct MutableInterface {
            var index: UInt32
            var kind: NetworkInterfaceKind
            var isUp: Bool
            var isRunning: Bool
            var addresses: Set<IPv4InterfaceAddress>
            var allAddresses: Set<String>
        }

        var collected: [String: MutableInterface] = [:]
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            defer { current = item.pointee.ifa_next }

            let name = String(cString: item.pointee.ifa_name)
            let flags = item.pointee.ifa_flags
            let kind = Self.interfaceKind(name: name, flags: flags)
            let isUp = flags & UInt32(IFF_UP) != 0
            let isRunning = flags & UInt32(IFF_RUNNING) != 0
            var value = collected[name] ?? MutableInterface(
                index: if_nametoindex(name),
                kind: kind,
                isUp: false,
                isRunning: false,
                addresses: [],
                allAddresses: []
            )
            value.kind = kind
            value.isUp = value.isUp || isUp
            value.isRunning = value.isRunning || isRunning

            if let socketAddress = item.pointee.ifa_addr,
               socketAddress.pointee.sa_family == UInt8(AF_INET),
               let address = Self.ipv4Address(from: socketAddress) {
                let prefixLength = item.pointee.ifa_netmask
                    .flatMap { Self.ipv4Address(from: UnsafePointer($0)) }
                    .flatMap(Self.prefixLength(from:)) ?? 32
                value.addresses.insert(IPv4InterfaceAddress(
                    address: address,
                    prefixLength: prefixLength
                ))
            }
            if let socketAddress = item.pointee.ifa_addr,
               let address = Self.ipAddressString(from: socketAddress) {
                value.allAddresses.insert(address)
            }
            collected[name] = value
        }

        let snapshots = collected.map { name, value -> NetworkInterfaceSnapshot in
            let services = serviceState[name, default: []].sorted {
                if ($0.router != nil) != ($1.router != nil) {
                    return $0.router != nil
                }
                return $0.serviceID < $1.serviceID
            }
            let selectedService = services.first
            return NetworkInterfaceSnapshot(
                name: name,
                index: value.index,
                serviceID: selectedService?.serviceID,
                kind: value.kind,
                isUp: value.isUp,
                isRunning: value.isRunning,
                isPrimary: name == primaryIPv4Interface || name == primaryIPv6Interface,
                addresses: value.addresses.sorted {
                    if $0.address != $1.address { return $0.address < $1.address }
                    return $0.prefixLength < $1.prefixLength
                },
                router: selectedService?.router,
                allAddresses: value.allAddresses.sorted()
            )
        }.sorted {
            if $0.index != $1.index { return $0.index < $1.index }
            return $0.name < $1.name
        }

        return NetworkTopologySnapshot(
            interfaces: snapshots,
            primaryIPv4InterfaceName: primaryIPv4Interface,
            primaryIPv6InterfaceName: primaryIPv6Interface
        )
    }

    private struct IPv4ServiceState {
        let serviceID: String
        let router: IPv4HostAddress?
    }

    private static func copyIPv4ServiceState() -> [String: [IPv4ServiceState]] {
        guard let store = SCDynamicStoreCreate(
            nil,
            "CellularModemMonitor.Topology" as CFString,
            nil,
            nil
        ), let keys = SCDynamicStoreCopyKeyList(
            store,
            #"^State:/Network/Service/[^/]+/IPv4$"# as CFString
        ) as? [String]
        else { return [:] }

        var result: [String: [IPv4ServiceState]] = [:]
        for key in keys.sorted() {
            guard let dictionary = SCDynamicStoreCopyValue(store, key as CFString)
                    as? [String: Any],
                  let interfaceName = dictionary[kSCPropInterfaceName as String] as? String,
                  let serviceID = serviceID(fromIPv4StateKey: key)
            else { continue }

            let router = (dictionary[kSCPropNetIPv4Router as String] as? String)
                .flatMap(IPv4HostAddress.init(string:))
            result[interfaceName, default: []].append(IPv4ServiceState(
                serviceID: serviceID,
                router: router
            ))
        }
        return result
    }

    private static func copyPrimaryInterfaceName(entity: CFString) -> String? {
        guard let store = SCDynamicStoreCreate(
            nil,
            "CellularModemMonitor.Topology.Primary" as CFString,
            nil,
            nil
        ) else { return nil }
        let key = SCDynamicStoreKeyCreateNetworkGlobalEntity(
            nil,
            kSCDynamicStoreDomainState,
            entity
        )
        guard let dictionary = SCDynamicStoreCopyValue(store, key) as? [String: Any]
        else { return nil }
        return dictionary[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }

    private static func serviceID(fromIPv4StateKey key: String) -> String? {
        let prefix = "State:/Network/Service/"
        let suffix = "/IPv4"
        guard key.hasPrefix(prefix), key.hasSuffix(suffix) else { return nil }
        let start = key.index(key.startIndex, offsetBy: prefix.count)
        let end = key.index(key.endIndex, offsetBy: -suffix.count)
        guard start < end else { return nil }
        return String(key[start..<end])
    }

    private static func interfaceKind(name: String, flags: UInt32) -> NetworkInterfaceKind {
        if flags & UInt32(IFF_LOOPBACK) != 0 || name == "lo0" {
            return .loopback
        }
        if flags & UInt32(IFF_POINTOPOINT) != 0 ||
            ["utun", "ipsec", "ppp", "gif", "stf"].contains(where: name.hasPrefix) {
            return .tunnel
        }
        if ["awdl", "llw", "p2p"].contains(where: name.hasPrefix) {
            return .peerToPeer
        }
        return .physical
    }

    private static func ipv4Address(
        from socketAddress: UnsafePointer<sockaddr>
    ) -> IPv4HostAddress? {
        guard socketAddress.pointee.sa_family == UInt8(AF_INET) else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        let address = UnsafeRawPointer(socketAddress)
            .assumingMemoryBound(to: sockaddr_in.self)
            .pointee.sin_addr
        var mutableAddress = address
        guard inet_ntop(
            AF_INET,
            &mutableAddress,
            &text,
            socklen_t(text.count)
        ) != nil else { return nil }
        let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return IPv4HostAddress(string: String(decoding: bytes, as: UTF8.self))
    }

    private static func ipAddressString(
        from socketAddress: UnsafePointer<sockaddr>
    ) -> String? {
        switch Int32(socketAddress.pointee.sa_family) {
        case AF_INET:
            return ipv4Address(from: socketAddress)?.description
        case AF_INET6:
            var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            var address = UnsafeRawPointer(socketAddress)
                .assumingMemoryBound(to: sockaddr_in6.self)
                .pointee.sin6_addr
            guard inet_ntop(
                AF_INET6,
                &address,
                &text,
                socklen_t(text.count)
            ) != nil else { return nil }
            let bytes = text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            return String(decoding: bytes, as: UTF8.self)
        default:
            return nil
        }
    }

    private static func prefixLength(from mask: IPv4HostAddress) -> UInt8? {
        let value = mask.rawValue
        if value == 0 { return 0 }
        let inverted = ~value
        guard inverted & (inverted &+ 1) == 0 else { return nil }
        return UInt8(value.nonzeroBitCount)
    }
}
