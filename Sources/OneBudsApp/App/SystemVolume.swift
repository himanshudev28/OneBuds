import AudioToolbox
import CoreAudio
import Observation

/// The Mac's current output device and its volume, kept live with CoreAudio property listeners.
/// Changes made elsewhere (keyboard keys, Control Center) appear here too.
@MainActor
@Observable
final class SystemVolume {
    private(set) var deviceName: String?
    /// 0…1.
    private(set) var volume: Float = 0
    private(set) var isMuted = false
    /// False when the output has no settable volume (some HDMI and digital outputs).
    private(set) var isAdjustable = false

    @ObservationIgnored private var deviceID = AudioObjectID(kAudioObjectUnknown)
    @ObservationIgnored private var started = false
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var valueListener: AudioObjectPropertyListenerBlock?

    private static var defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private static var mainVolume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    private static var mute = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    func start() {
        guard !started else { return }
        started = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.followDefaultDevice() }
        }
        deviceListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutput, .main, listener)
        followDefaultDevice()
    }

    /// Whether the output device looks like the given earbuds (macOS names the device after them).
    func isOutput(named name: String?) -> Bool {
        guard let name, let deviceName else { return false }
        return deviceName.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains(deviceName)
    }

    func setVolume(_ value: Float) {
        var scalar = Float32(min(max(value, 0), 1))
        guard isAdjustable,
              AudioObjectSetPropertyData(deviceID, &Self.mainVolume, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr
        else { return }
        volume = scalar
        if isMuted, scalar > 0 { setMuted(false) }
    }

    func setMuted(_ muted: Bool) {
        var value: UInt32 = muted ? 1 : 0
        guard AudioObjectHasProperty(deviceID, &Self.mute),
              AudioObjectSetPropertyData(deviceID, &Self.mute, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
        else { return }
        isMuted = muted
    }

    // MARK: Private

    private func followDefaultDevice() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutput, 0, nil, &size, &id) == noErr else {
            removeValueListeners()
            deviceID = AudioObjectID(kAudioObjectUnknown)
            deviceName = nil
            isAdjustable = false
            return
        }
        if id != deviceID {
            removeValueListeners()
            deviceID = id
            addValueListeners()
        }
        deviceName = name(of: id)
        readValues()
    }

    private func readValues() {
        var scalar = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var settable: DarwinBoolean = false
        let hasVolume = AudioObjectHasProperty(deviceID, &Self.mainVolume)
            && AudioObjectIsPropertySettable(deviceID, &Self.mainVolume, &settable) == noErr && settable.boolValue
            && AudioObjectGetPropertyData(deviceID, &Self.mainVolume, 0, nil, &size, &scalar) == noErr
        isAdjustable = hasVolume
        if hasVolume { volume = scalar }
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        isMuted = AudioObjectHasProperty(deviceID, &Self.mute)
            && AudioObjectGetPropertyData(deviceID, &Self.mute, 0, nil, &size, &muted) == noErr && muted != 0
    }

    private func addValueListeners() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.readValues() }
        }
        valueListener = listener
        AudioObjectAddPropertyListenerBlock(deviceID, &Self.mainVolume, .main, listener)
        AudioObjectAddPropertyListenerBlock(deviceID, &Self.mute, .main, listener)
    }

    private func removeValueListeners() {
        guard let listener = valueListener, deviceID != kAudioObjectUnknown else { return }
        AudioObjectRemovePropertyListenerBlock(deviceID, &Self.mainVolume, .main, listener)
        AudioObjectRemovePropertyListenerBlock(deviceID, &Self.mute, .main, listener)
        valueListener = nil
    }

    private func name(of id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }
}
