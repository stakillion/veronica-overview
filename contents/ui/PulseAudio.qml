import QtQuick
import org.kde.plasma.private.volume as PlasmaPa
import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet

Item {
    id: pulseAudio
    visible: false
    width: 0
    height: 0

    signal streamsChanged()

    property int streamsVersion: 0

    function notifyChanged() {
        pulseAudio.streamsVersion++;
        pulseAudio.streamsChanged();
    }

    property var pidMatches: new Set()

    TaskManagerApplet.Backend {
        id: backend
    }

    Connections {
        target: instantiator.model
        function onDataChanged() {
            pulseAudio.notifyChanged();
        }
    }

    Connections {
        target: sourceInstantiator.model
        function onDataChanged() {
            pulseAudio.notifyChanged();
        }
    }

    function registerPidMatch(appName) {
        if (!hasPidMatch(appName)) {
            pidMatches.add(appName);
            notifyChanged();
        }
    }

    function hasPidMatch(appName) {
        return pidMatches.has(appName);
    }

    function findStreamsFn(fn) {
        const streams = [];
        for (let i = 0, count = instantiator.count; i < count; ++i) {
            const stream = instantiator.objectAt(i);
            if (stream && fn(stream)) {
                streams.push(stream);
            }
        }
        return streams;
    }

    function normalizeAppId(id) {
        if (!id) return "";
        let s = String(id).trim().toLowerCase();
        if (s.endsWith(".desktop")) {
            s = s.substring(0, s.length - 8);
        }
        return s;
    }

    function matchStreamToApp(stream, appId, pid, appName) {
        if (!stream) return false;

        const sPid = stream.pid || 0;
        const sPortal = normalizeAppId(stream.portalAppId);
        const sBin = normalizeAppId(stream.binary);
        const sApp = (stream.appName || "").trim().toLowerCase();

        const normId = normalizeAppId(appId);
        const normName = appName ? String(appName).trim().toLowerCase() : "";

        // 1. Direct PID match (native host process)
        if (pid && pid > 0 && sPid > 0 && !sPortal && sPid === pid) {
            return true;
        }

        // 2. Flatpak / Portal App ID match
        if (sPortal && normId) {
            if (sPortal === normId
                || normId.endsWith("." + sPortal)
                || sPortal.endsWith("." + normId)) {
                return true;
            }
        }

        // 3. Binary vs Desktop App ID match (e.g. binary "discord", appId "discord" or "com.discordapp.Discord")
        if (sBin && normId && sBin.length >= 3) {
            if (sBin === normId
                || normId.endsWith("." + sBin)
                || normId.startsWith(sBin + ".")
                || normId.startsWith(sBin + "-")
                || normId.endsWith("-" + sBin)) {
                return true;
            }
        }

        // 4. Steam games (e.g. steam_app_12345 matching steam or steam portal)
        if (normId.startsWith("steam_app_")) {
            if (sBin === "steam" || (sPortal && sPortal.indexOf("steam") !== -1)) {
                return true;
            }
        }

        // 5. Application name match
        if (sApp && normName && sApp.length >= 3 && normName.length >= 3) {
            if (sApp === normName || sApp === "[" + normName + "]") {
                return true;
            }
            if (sBin && (sBin === normName || normName === sBin)) {
                return true;
            }
        }

        return false;
    }

    function getStreamsForCard(appId, pid, appName) {
        if (!appId && (!pid || pid <= 0) && !appName) return [];
        const streams = [];
        for (let i = 0, count = instantiator.count; i < count; ++i) {
            const stream = instantiator.objectAt(i);
            if (stream && matchStreamToApp(stream, appId, pid, appName)) {
                streams.push(stream);
            }
        }
        return streams;
    }

    function getMicStreamsForCard(appId, pid, appName) {
        if (!appId && (!pid || pid <= 0) && !appName) return [];
        const streams = [];
        for (let i = 0, count = sourceInstantiator.count; i < count; ++i) {
            const stream = sourceInstantiator.objectAt(i);
            if (stream && stream.isMicrophoneStream && matchStreamToApp(stream, appId, pid, appName)) {
                streams.push(stream);
            }
        }
        return streams;
    }

    function streamsForAppId(appId) {
        const norm = normalizeAppId(appId);
        if (!norm) return [];
        return findStreamsFn(stream => {
            const sp = normalizeAppId(stream.portalAppId);
            return sp && (sp === norm || sp.indexOf(norm) !== -1 || norm.indexOf(sp) !== -1);
        });
    }

    function streamsForAppName(appName) {
        if (!appName) return [];
        const lower = String(appName).trim().toLowerCase();
        return findStreamsFn(stream => {
            const aName = (stream.appName || "").toLowerCase();
            const bName = (stream.binary || "").toLowerCase();
            return aName === lower || bName === lower
                || aName.indexOf("[" + lower + "]") !== -1
                || (bName && lower.indexOf(bName) !== -1);
        });
    }

    function streamsForPid(pid) {
        if (!pid || pid <= 0) return [];
        const streams = findStreamsFn(stream => stream.pid === pid && !stream.portalAppId);

        if (streams.length === 0) {
            for (let i = 0, length = instantiator.count; i < length; ++i) {
                const stream = instantiator.objectAt(i);
                if (!stream) continue;

                if (stream.parentPid === -1 && backend) {
                    stream.parentPid = backend.parentPid(stream.pid);
                }

                if (stream.parentPid === pid) {
                    streams.push(stream);
                }
            }
        }

        return streams;
    }

    readonly property Instantiator instantiator: Instantiator {
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [ { role: "VirtualStream", value: false } ]
            sourceModel: PlasmaPa.SinkInputModel {}
        }

        delegate: QtObject {
            id: delegate
            required property var model
            readonly property int pid: model.Client ? (model.Client.properties ? (model.Client.properties["application.process.id"] || 0) : 0) : 0
            property int parentPid: -1
            readonly property string appName: model.Client ? (model.Client.properties ? (model.Client.properties["application.name"] || "") : "") : ""
            readonly property string binary: model.Client ? (model.Client.properties ? (model.Client.properties["application.process.binary"] || "") : "") : ""
            readonly property string portalAppId: model.Client ? (model.Client.properties ? (model.Client.properties["pipewire.access.portal.app_id"] || "") : "") : ""
            readonly property bool muted: Boolean(model.PulseObject ? model.PulseObject.muted : model.Muted)
            readonly property bool corked: Boolean(model.Corked)
            readonly property int volume: model.Volume || 0
            readonly property int streamIndex: model.Index !== undefined ? model.Index : (model.PulseObject ? model.PulseObject.index : index)

            onPidChanged: pulseAudio.notifyChanged()
            onCorkedChanged: pulseAudio.notifyChanged()
            onMutedChanged: pulseAudio.notifyChanged()
            onAppNameChanged: pulseAudio.notifyChanged()
            onPortalAppIdChanged: pulseAudio.notifyChanged()

            function mute() {
                if (model.PulseObject && typeof model.PulseObject.setMuted === 'function') {
                    model.PulseObject.setMuted(true);
                } else if (model.PulseObject && model.PulseObject.muted !== undefined) {
                    model.PulseObject.muted = true;
                }
                try { model.Muted = true; } catch (_) {}
                pulseAudio.notifyChanged();
            }
            function unmute() {
                if (model.PulseObject && typeof model.PulseObject.setMuted === 'function') {
                    model.PulseObject.setMuted(false);
                } else if (model.PulseObject && model.PulseObject.muted !== undefined) {
                    model.PulseObject.muted = false;
                }
                try { model.Muted = false; } catch (_) {}
                pulseAudio.notifyChanged();
            }
        }

        onObjectAdded: (index, object) => pulseAudio.notifyChanged()
        onObjectRemoved: (index, object) => pulseAudio.notifyChanged()
    }

    function findSourceStreamsFn(fn) {
        const streams = [];
        for (let i = 0, count = sourceInstantiator.count; i < count; ++i) {
            const stream = sourceInstantiator.objectAt(i);
            if (stream && stream.isMicrophoneStream && fn(stream)) {
                streams.push(stream);
            }
        }
        return streams;
    }

    function micStreamsForAppId(appId) {
        const norm = normalizeAppId(appId);
        if (!norm) return [];
        return findSourceStreamsFn(stream => {
            const sp = normalizeAppId(stream.portalAppId);
            if (!sp) return false;
            if (sp === norm) return true;
            if (sp.indexOf("discord") !== -1 && norm.indexOf("discord") !== -1) return true;
            return false;
        });
    }

    function micStreamsForAppName(appName) {
        if (!appName) return [];
        const lower = String(appName).trim().toLowerCase();
        if (lower.length < 2) return [];
        return findSourceStreamsFn(stream => {
            const aName = (stream.appName || "").toLowerCase();
            const bName = (stream.binary || "").toLowerCase();
            if (bName && (bName === lower || lower === bName + ".desktop")) return true;
            if (aName && (aName === lower || aName === "[" + lower + "]")) return true;
            return false;
        });
    }

    function micStreamsForPid(pid) {
        if (!pid || pid <= 0) return [];
        return findSourceStreamsFn(stream => !stream.portalAppId && stream.pid > 0 && stream.pid === pid);
    }

    readonly property Instantiator sourceInstantiator: Instantiator {
        model: PlasmaPa.PulseObjectFilterModel {
            filters: [ { role: "VirtualStream", value: false } ]
            sourceModel: PlasmaPa.SourceOutputModel {}
        }

        delegate: QtObject {
            id: sourceDelegate
            required property var model
            readonly property int pid: model.Client ? (model.Client.properties ? (model.Client.properties["application.process.id"] || 0) : 0) : 0
            property int parentPid: -1
            readonly property string appName: model.Client ? (model.Client.properties ? (model.Client.properties["application.name"] || "") : "") : ""
            readonly property string binary: model.Client ? (model.Client.properties ? (model.Client.properties["application.process.binary"] || "") : "") : ""
            readonly property string portalAppId: model.Client ? (model.Client.properties ? (model.Client.properties["pipewire.access.portal.app_id"] || "") : "") : ""
            readonly property bool muted: Boolean(model.PulseObject ? model.PulseObject.muted : model.Muted)
            readonly property bool corked: Boolean(model.Corked)
            readonly property int volume: model.Volume || 0
            readonly property int streamIndex: model.Index !== undefined ? model.Index : (model.PulseObject ? model.PulseObject.index : index)
            readonly property int deviceIndex: model.PulseObject ? (model.PulseObject.deviceIndex !== undefined ? model.PulseObject.deviceIndex : -1) : -1

            readonly property var streamProps: model.PulseObject ? model.PulseObject.properties : null
            readonly property string mediaName: streamProps ? (streamProps["media.name"] || "") : ""
            readonly property string mediaRole: streamProps ? (streamProps["media.role"] || "") : ""

            // Strict microphone validation:
            // 1. Must have a valid client
            // 2. Must be connected to a valid source device (not -1 / 4294967295)
            // 3. Must NOT be an internal desktop/game audio loopback capture (e.g. discord_capture, game capture)
            // 4. Must NOT be a screen or video recording monitor
            readonly property bool isMicrophoneStream: {
                if (!model.Client) return false;
                if (deviceIndex < 0 || deviceIndex === 4294967295) return false;
                if (appName === "discord_capture" || mediaName === "game capture") return false;
                if (mediaRole === "screen" || mediaRole === "video") return false;
                return true;
            }

            onPidChanged: pulseAudio.notifyChanged()
            onCorkedChanged: pulseAudio.notifyChanged()
            onMutedChanged: pulseAudio.notifyChanged()
            onAppNameChanged: pulseAudio.notifyChanged()
            onPortalAppIdChanged: pulseAudio.notifyChanged()

            function mute() {
                if (model.PulseObject && typeof model.PulseObject.setMuted === 'function') {
                    model.PulseObject.setMuted(true);
                } else if (model.PulseObject && model.PulseObject.muted !== undefined) {
                    model.PulseObject.muted = true;
                }
                try { model.Muted = true; } catch (_) {}
                pulseAudio.notifyChanged();
            }
            function unmute() {
                if (model.PulseObject && typeof model.PulseObject.setMuted === 'function') {
                    model.PulseObject.setMuted(false);
                } else if (model.PulseObject && model.PulseObject.muted !== undefined) {
                    model.PulseObject.muted = false;
                }
                try { model.Muted = false; } catch (_) {}
                pulseAudio.notifyChanged();
            }
        }

        onObjectAdded: (index, object) => pulseAudio.notifyChanged()
        onObjectRemoved: (index, object) => pulseAudio.notifyChanged()
    }
}
