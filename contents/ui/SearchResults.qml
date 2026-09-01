import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.milou as Milou

Rectangle {
    id: root

    property string query: ""
    signal itemActivated()

    radius: 16
    color: Qt.rgba(0.12, 0.12, 0.14, 0.96)
    border.width: 0
    clip: true

    function activateCurrent() {
        if (resultsView.currentIndex < 0 && resultsView.count > 0) {
            resultsView.currentIndex = 0;
        }
        resultsView.runCurrentIndex();
    }

    function selectNext() {
        if (resultsView.currentIndex < resultsView.count - 1) {
            resultsView.currentIndex++;
            resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
        }
    }

    function selectPrevious() {
        if (resultsView.currentIndex > 0) {
            resultsView.currentIndex--;
            resultsView.positionViewAtIndex(resultsView.currentIndex, ListView.Contain);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                text: i18n("Search Results for \"%1\"", root.query)
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize + 1
                color: Qt.rgba(1, 1, 1, 0.90)
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        Milou.ResultsView {
            id: resultsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            queryString: root.query
            onActivated: root.itemActivated()
        }
    }
}
