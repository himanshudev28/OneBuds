/// A framework-free copy of an SDP data element (Bluetooth Core spec Vol 3 Part B §3).
/// The probe converts `IOBluetoothSDPDataElement` into this so parsing can be unit-tested.
public indirect enum SDPValue: Sendable, Equatable, Codable {
    case null
    case unsignedInt(UInt64, bytes: Int)
    case signedInt(Int64, bytes: Int)
    /// Integer too wide for 64 bits (e.g. 128-bit), kept as raw hex.
    case wideInt(hex: String, signed: Bool)
    case uuid(String)
    case string(String)
    case bool(Bool)
    case sequence([SDPValue])
    case alternative([SDPValue])
    case url(String)
    case unknown(typeDescriptor: Int)
}

/// Well-known SDP attribute IDs (Bluetooth Assigned Numbers, "Service Discovery").
public enum SDPAttributeID {
    public static let serviceRecordHandle: UInt16 = 0x0000
    public static let serviceClassIDList: UInt16 = 0x0001
    public static let protocolDescriptorList: UInt16 = 0x0004
    public static let browseGroupList: UInt16 = 0x0005
    public static let bluetoothProfileDescriptorList: UInt16 = 0x0009
    public static let additionalProtocolDescriptorLists: UInt16 = 0x000D
    /// 0x0100 + language base offset (normally 0x0100).
    public static let serviceName: UInt16 = 0x0100
    public static let serviceDescription: UInt16 = 0x0101
    public static let providerName: UInt16 = 0x0102

    public static func name(for id: UInt16, serviceClasses: [String] = []) -> String {
        if serviceClasses.contains(pnpInformation) {
            switch id {
            case 0x0200: return "SpecificationID"
            case 0x0201: return "VendorID"
            case 0x0202: return "ProductID"
            case 0x0203: return "Version"
            case 0x0204: return "PrimaryRecord"
            case 0x0205: return "VendorIDSource"
            default: break
            }
        }
        switch id {
        case 0x0000: return "ServiceRecordHandle"
        case 0x0001: return "ServiceClassIDList"
        case 0x0002: return "ServiceRecordState"
        case 0x0003: return "ServiceID"
        case 0x0004: return "ProtocolDescriptorList"
        case 0x0005: return "BrowseGroupList"
        case 0x0006: return "LanguageBaseAttributeIDList"
        case 0x0007: return "ServiceInfoTimeToLive"
        case 0x0008: return "ServiceAvailability"
        case 0x0009: return "BluetoothProfileDescriptorList"
        case 0x000A: return "DocumentationURL"
        case 0x000B: return "ClientExecutableURL"
        case 0x000C: return "IconURL"
        case 0x000D: return "AdditionalProtocolDescriptorLists"
        case 0x0100: return "ServiceName"
        case 0x0101: return "ServiceDescription"
        case 0x0102: return "ProviderName"
        case 0x0311: return "SupportedFeatures"
        default: return String(format: "Attribute 0x%04X", id)
        }
    }

    static let pnpInformation = "00001200-0000-1000-8000-00805F9B34FB"
}

public enum SDPParsing {
    /// UUIDs listed in a ServiceClassIDList value.
    /// Observed 2026-10-12: IOBluetooth returns a one-entry ServiceClassIDList as a bare UUID
    /// rather than a sequence, so both shapes are accepted.
    public static func serviceClassUUIDs(_ value: SDPValue?) -> [String] {
        switch value {
        case .uuid(let uuid)?: return [uuid]
        case .sequence(let items)?: return items.compactMap { if case .uuid(let uuid) = $0 { uuid } else { nil } }
        default: return []
        }
    }

    /// RFCOMM server channel from a ProtocolDescriptorList such as
    /// `((L2CAP), (RFCOMM, 15))`. Returns `nil` when there is no RFCOMM layer.
    public static func rfcommChannel(fromProtocolDescriptorList value: SDPValue?) -> UInt8? {
        guard case .sequence(let layers)? = value else { return nil }
        let rfcomm = BluetoothUUID.canonical(fromBytes: [0x00, 0x03])!
        for layer in layers {
            guard case .sequence(let parts) = layer, parts.count >= 2,
                  case .uuid(let uuid) = parts[0], uuid == rfcomm,
                  case .unsignedInt(let channel, _) = parts[1], channel <= UInt64(UInt8.max) else { continue }
            return UInt8(channel)
        }
        return nil
    }

    /// L2CAP PSM from a ProtocolDescriptorList, when one is declared.
    public static func l2capPSM(fromProtocolDescriptorList value: SDPValue?) -> UInt16? {
        guard case .sequence(let layers)? = value else { return nil }
        let l2cap = BluetoothUUID.canonical(fromBytes: [0x01, 0x00])!
        for layer in layers {
            guard case .sequence(let parts) = layer, parts.count >= 2,
                  case .uuid(let uuid) = parts[0], uuid == l2cap,
                  case .unsignedInt(let psm, _) = parts[1], psm <= UInt64(UInt16.max) else { continue }
            return UInt16(psm)
        }
        return nil
    }

    /// Human-readable one-line rendering, annotating known UUIDs.
    public static func render(_ value: SDPValue) -> String {
        switch value {
        case .null: return "nil"
        case .unsignedInt(let v, let bytes): return String(format: "0x%0\(max(bytes, 1) * 2)llX", v)
        case .signedInt(let v, _): return "\(v)"
        case .wideInt(let hex, let signed): return "\(signed ? "int" : "uint")128 0x\(hex)"
        case .uuid(let uuid):
            let short = BluetoothUUID.shortForm(uuid).map { "0x\($0)" } ?? uuid
            if let known = KnownUUIDs.lookup(uuid) { return "\(short) [\(known.label)]" }
            return short
        case .string(let s): return "\"\(s)\""
        case .bool(let b): return b ? "true" : "false"
        case .sequence(let items): return "(" + items.map(render).joined(separator: ", ") + ")"
        case .alternative(let items): return "alt(" + items.map(render).joined(separator: " | ") + ")"
        case .url(let url): return "url(\(url))"
        case .unknown(let type): return "<unknown SDP type \(type)>"
        }
    }
}
