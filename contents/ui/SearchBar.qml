import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property alias text: searchInput.text
    property alias placeholderText: placeholderLabel.text
    property alias searchField: searchInput

    signal searchCleared()
    signal searchFieldFocused()
    signal accepted()
    signal moveSelectionDown()
    signal moveSelectionUp()
    signal escapePressed()

    width: Math.min(parent ? Math.max(380, parent.width * 0.45) : 480, 540)
    height: 44
    radius: 22

    color: Qt.rgba(0.18, 0.18, 0.20, 0.88)
    border.width: searchInput.activeFocus ? 2 : 1
    border.color: searchInput.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.22)

    Behavior on border.color { ColorAnimation { duration: 150 } }

    focus: true

    function forceFocus() {
        searchInput.forceActiveFocus();
        searchInput.cursorPosition = searchInput.text.length;
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        z: -1
        onClicked: {
            root.forceFocus();
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 10
        spacing: 8

        Kirigami.Icon {
            source: "search"
            implicitWidth: 18
            implicitHeight: 18
            color: searchInput.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(1, 1, 1, 0.65)
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        TextInput {
            id: searchInput
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            color: "#ffffff"
            font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
            clip: true
            selectByMouse: true
            selectionColor: Kirigami.Theme.highlightColor
            focus: false
            activeFocusOnTab: true

            onActiveFocusChanged: {
                if (activeFocus) {
                    root.searchFieldFocused();
                }
            }

            onTextEdited: {
                searchInput.forceActiveFocus(Qt.ShortcutFocusReason);
            }

            QQC2.Label {
                id: placeholderLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: i18n("Type to search…")
                color: Qt.rgba(1, 1, 1, 0.45)
                font: searchInput.font
                visible: !searchInput.text && !searchInput.inputMethodComposing
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    event.accepted = false;
                    return;
                }
                if (event.key === Qt.Key_Escape) {
                    root.escapePressed();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down) {
                    root.moveSelectionDown();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.moveSelectionUp();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.accepted();
                    event.accepted = true;
                }
            }
        }

        // Clear search text button
        Rectangle {
            id: clearBtn
            visible: searchInput.text.length > 0
            width: 22
            height: 22
            radius: 11
            color: clearMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)

            Kirigami.Icon {
                anchors.centerIn: parent
                source: "edit-clear-symbolic"
                implicitWidth: 14
                implicitHeight: 14
                color: "#ffffff"
            }

            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    searchInput.text = "";
                    root.searchCleared();
                }
            }
        }
    }
}
