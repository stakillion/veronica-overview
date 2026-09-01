pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
    id: root

    required property PlasmoidItem plasmoidItem

    readonly property bool vertical: (Plasmoid.formFactor === PlasmaCore.Types.Vertical)

    // Config options
    readonly property bool rawShowIcon: Plasmoid.configuration.showButtonIcon ?? true
    readonly property bool rawShowText: Plasmoid.configuration.showButtonText ?? false
    readonly property bool showIcon: rawShowIcon || !rawShowText
    readonly property bool showText: rawShowText
    readonly property string buttonText: Plasmoid.configuration.buttonText || i18n("Activities")

    implicitWidth: {
        if (vertical) {
            return Kirigami.Units.iconSizes.medium;
        } else {
            if (showText) {
                return (showIcon ? height + buttonLabel.implicitWidth + 8 : buttonLabel.implicitWidth + 12);
            }
            return height;
        }
    }

    implicitHeight: {
        if (vertical) {
            if (showText) {
                return (showIcon ? width + verticalLabel.implicitHeight + 8 : verticalLabel.implicitHeight + 12);
            }
            return width;
        } else {
            return Kirigami.Units.iconSizes.medium;
        }
    }

    Layout.minimumWidth: vertical ? 0 : implicitWidth
    Layout.preferredWidth: vertical ? -1 : implicitWidth
    Layout.minimumHeight: vertical ? implicitHeight : 0
    Layout.preferredHeight: vertical ? implicitHeight : -1
    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical

    // Native KDE Plasma Panel Active Tab / Button Indicator
    KSvg.FrameSvgItem {
        id: expandedIndicator
        z: -100

        property var containerMargins: {
            let item = root;
            while (item.parent) {
                item = item.parent;
                if (item.isAppletContainer || item.getMargins !== undefined) {
                    return item.getMargins;
                }
            }
            return undefined;
        }

        anchors {
            fill: parent
            property bool returnAllMargins: true
            bottomMargin: !vertical && containerMargins ? -containerMargins('bottom', returnAllMargins) : 0
            topMargin: !vertical && containerMargins ? -containerMargins('top', returnAllMargins) : 0
            leftMargin: vertical && containerMargins ? -containerMargins('left', returnAllMargins) : 0
            rightMargin: vertical && containerMargins ? -containerMargins('right', returnAllMargins) : 0
        }

        imagePath: "widgets/tabbar"
        prefix: {
            let p;
            switch (Plasmoid.location) {
            case PlasmaCore.Types.LeftEdge:
                p = "west-active-tab";
                break;
            case PlasmaCore.Types.TopEdge:
                p = "north-active-tab";
                break;
            case PlasmaCore.Types.RightEdge:
                p = "east-active-tab";
                break;
            default:
                p = "south-active-tab";
            }
            if (!hasElementPrefix(p)) {
                p = "active-tab";
            }
            return p;
        }
        visible: opacity > 0
        opacity: (root.plasmoidItem.isOverviewOpen || mouseArea.pressed) ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Kirigami.Units.shortDuration
                easing.type: Easing.InOutQuad
            }
        }
    }

    // 1. Icon-only mode (Strict 1:1 match with Application Launcher DefaultCompactRepresentation)
    Kirigami.Icon {
        id: soloIcon
        visible: !root.showText && root.showIcon
        anchors.fill: parent
        source: root.plasmoidItem.iconName || "search"
        active: mouseArea.containsMouse || root.plasmoidItem.isOverviewOpen
    }

    // 2. Horizontal Icon + Text mode
    RowLayout {
        id: horizontalContent
        visible: !root.vertical && root.showText
        anchors.fill: parent
        spacing: 6

        Kirigami.Icon {
            id: horizontalIcon
            visible: root.showIcon
            Layout.fillHeight: true
            Layout.preferredWidth: height
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            source: root.plasmoidItem.iconName || "search"
            active: mouseArea.containsMouse || root.plasmoidItem.isOverviewOpen
        }

        QQC2.Label {
            id: buttonLabel
            visible: root.showText
            text: root.buttonText
            font.family: Plasmoid.configuration.buttonFontFamily ? Plasmoid.configuration.buttonFontFamily : Kirigami.Theme.defaultFont.family
            font.pointSize: (Plasmoid.configuration.buttonFontSize > 0) ? Plasmoid.configuration.buttonFontSize : Kirigami.Theme.defaultFont.pointSize
            font.bold: Plasmoid.configuration.buttonFontBold ?? false
            font.italic: Plasmoid.configuration.buttonFontItalic ?? false
            font.weight: (Plasmoid.configuration.buttonFontWeight > 0) ? Plasmoid.configuration.buttonFontWeight : Font.Normal
            font.styleName: Plasmoid.configuration.buttonFontStyleName || ""
            color: Kirigami.Theme.textColor
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    // 3. Vertical Icon + Text mode
    ColumnLayout {
        id: verticalContent
        visible: root.vertical && root.showText
        anchors.fill: parent
        spacing: 4

        Kirigami.Icon {
            id: verticalIcon
            visible: root.showIcon
            Layout.fillWidth: true
            Layout.preferredHeight: width
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            source: root.plasmoidItem.iconName || "search"
            active: mouseArea.containsMouse || root.plasmoidItem.isOverviewOpen
        }

        QQC2.Label {
            id: verticalLabel
            visible: root.showText
            text: root.buttonText
            font.family: Plasmoid.configuration.buttonFontFamily ? Plasmoid.configuration.buttonFontFamily : Kirigami.Theme.defaultFont.family
            font.pointSize: (Plasmoid.configuration.buttonFontSize > 0) ? Plasmoid.configuration.buttonFontSize : Kirigami.Theme.defaultFont.pointSize
            font.bold: Plasmoid.configuration.buttonFontBold ?? false
            font.italic: Plasmoid.configuration.buttonFontItalic ?? false
            font.weight: (Plasmoid.configuration.buttonFontWeight > 0) ? Plasmoid.configuration.buttonFontWeight : Font.Normal
            font.styleName: Plasmoid.configuration.buttonFontStyleName || ""
            color: Kirigami.Theme.textColor
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            root.plasmoidItem.toggleOverview();
        }
    }
}
