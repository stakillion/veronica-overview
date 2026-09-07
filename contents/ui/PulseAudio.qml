import QtQuick
import org.kde.plasma.private.volume as PlasmaPa
import plasma.applet.org.kde.plasma.taskmanager as TaskManagerApplet

Item {
    id: pulseAudio
    visible: false
    width: 0
    height: 0

    signal streamsChanged()

    property var pidMatches: new Set()

    TaskManagerApplet.Backend {
        id: backend
    }

    Connections {
        target: instantiator.model
        function onDataChanged() {
            pulseAudio.streamsChanged();
        }
    }

    function registerPidMatch(appName) {
        if (!hasPidMatch(appName)) {
            pidMatches.add(appName);
            streamsChanged();
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
            readonly property bool muted: Boolean(model.Muted)
            readonly property bool corked: Boolean(model.Corked)
            readonly property int volume: model.Volume || 0
            readonly property int streamIndex: model.Index !== undefined ? model.Index : (model.PulseObject ? model.PulseObject.index : index)

            onPidChanged: pulseAudio.streamsChanged()
            onCorkedChanged: pulseAudio.streamsChanged()
            onMutedChanged: pulseAudio.streamsChanged()
            onAppNameChanged: pulseAudio.streamsChanged()
            onPortalAppIdChanged: pulseAudio.streamsChanged()

            function mute() {
                model.Muted = true;
            }
            function unmute() {
                model.Muted = false;
            }
        }

        onObjectAdded: (index, object) => pulseAudio.streamsChanged()
        onObjectRemoved: (index, object) => pulseAudio.streamsChanged()
    }
}
