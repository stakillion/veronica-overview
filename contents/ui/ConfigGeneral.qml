import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import org.kde.plasma.plasmoid

Kirigami.FormLayout {
    id: root

    property alias cfg_icon: iconButton.iconName
    property alias cfg_buttonText: buttonTextField.text
    property alias cfg_showButtonText: showButtonTextCheckBox.checked
    property alias cfg_showButtonIcon: showButtonIconCheckBox.checked
    property string cfg_buttonFontFamily: Plasmoid.configuration.buttonFontFamily !== undefined ? Plasmoid.configuration.buttonFontFamily : ""
    property int cfg_buttonFontSize: Plasmoid.configuration.buttonFontSize !== undefined ? Plasmoid.configuration.buttonFontSize : 0
    property bool cfg_buttonFontBold: Plasmoid.configuration.buttonFontBold !== undefined ? Plasmoid.configuration.buttonFontBold : false
    property bool cfg_buttonFontItalic: Plasmoid.configuration.buttonFontItalic !== undefined ? Plasmoid.configuration.buttonFontItalic : false
    property int cfg_buttonFontWeight: Plasmoid.configuration.buttonFontWeight !== undefined ? Plasmoid.configuration.buttonFontWeight : 400
    property string cfg_buttonFontStyleName: Plasmoid.configuration.buttonFontStyleName !== undefined ? Plasmoid.configuration.buttonFontStyleName : ""

    property alias cfg_showWorkspaceStrip: showWorkspaceStripCheckBox.checked
    property alias cfg_showCloseButtons: showCloseButtonsCheckBox.checked
    property alias cfg_hasBottomPanel: hasBottomPanelCheckBox.checked

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Panel Icon & Button")
    }

    KIconThemes.IconDialog {
        id: iconDialog
        onIconNameChanged: iconButton.iconName = iconName
    }

    FontDialog {
        id: fontDialog
        title: i18n("Choose Button Font")
        onAccepted: {
            root.cfg_buttonFontFamily = selectedFont.family;
            if (selectedFont.pointSize > 0) {
                root.cfg_buttonFontSize = Math.round(selectedFont.pointSize);
            } else if (selectedFont.pixelSize > 0) {
                root.cfg_buttonFontSize = Math.round(selectedFont.pixelSize);
            }
            root.cfg_buttonFontBold = selectedFont.bold;
            root.cfg_buttonFontItalic = selectedFont.italic;
            root.cfg_buttonFontWeight = selectedFont.weight;
            root.cfg_buttonFontStyleName = selectedFont.styleName ? selectedFont.styleName : "";
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Icon:")
        QQC2.Button {
            id: iconButton
            property string iconName: "search"
            icon.name: iconName
            text: iconName ? iconName : i18n("Choose…")
            onClicked: iconDialog.open()
        }
        QQC2.Button {
            text: i18n("Reset to Default")
            icon.name: "edit-undo"
            onClicked: iconButton.iconName = "search"
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Display options:")
        QQC2.CheckBox {
            id: showButtonIconCheckBox
            text: i18n("Show icon")
        }
        QQC2.CheckBox {
            id: showButtonTextCheckBox
            text: i18n("Show text")
        }
    }

    QQC2.TextField {
        id: buttonTextField
        Kirigami.FormData.label: i18n("Button text:")
        placeholderText: i18n("Activities")
        visible: showButtonTextCheckBox.checked
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Font:")
        visible: showButtonTextCheckBox.checked

        QQC2.Label {
            id: fontPreviewLabel
            text: {
                if (!root.cfg_buttonFontFamily) {
                    return i18n("System Default");
                }
                let desc = root.cfg_buttonFontFamily;
                if (root.cfg_buttonFontSize > 0) {
                    desc += " " + root.cfg_buttonFontSize + "pt";
                }
                let styles = [];
                if (root.cfg_buttonFontStyleName) {
                    styles.push(root.cfg_buttonFontStyleName);
                } else {
                    if (root.cfg_buttonFontBold) styles.push(i18n("Bold"));
                    if (root.cfg_buttonFontItalic) styles.push(i18n("Italic"));
                }
                if (styles.length > 0) {
                    desc += " (" + styles.join(", ") + ")";
                }
                return desc;
            }
            font.family: root.cfg_buttonFontFamily ? root.cfg_buttonFontFamily : Kirigami.Theme.defaultFont.family
            font.bold: root.cfg_buttonFontBold
            font.italic: root.cfg_buttonFontItalic
            font.weight: root.cfg_buttonFontWeight > 0 ? root.cfg_buttonFontWeight : Font.Normal
            Layout.alignment: Qt.AlignVCenter
        }

        QQC2.Button {
            text: i18n("Choose…")
            icon.name: "preferences-desktop-font"
            onClicked: {
                if (root.cfg_buttonFontFamily) {
                    fontDialog.currentFont.family = root.cfg_buttonFontFamily;
                }
                if (root.cfg_buttonFontSize > 0) {
                    fontDialog.currentFont.pointSize = root.cfg_buttonFontSize;
                }
                fontDialog.currentFont.bold = root.cfg_buttonFontBold;
                fontDialog.currentFont.italic = root.cfg_buttonFontItalic;
                if (root.cfg_buttonFontWeight > 0) {
                    fontDialog.currentFont.weight = root.cfg_buttonFontWeight;
                }
                if (root.cfg_buttonFontStyleName) {
                    fontDialog.currentFont.styleName = root.cfg_buttonFontStyleName;
                }
                fontDialog.open();
            }
        }

        QQC2.Button {
            text: i18n("Reset Font")
            icon.name: "edit-undo"
            onClicked: {
                root.cfg_buttonFontFamily = "";
                root.cfg_buttonFontSize = 0;
                root.cfg_buttonFontBold = false;
                root.cfg_buttonFontItalic = false;
                root.cfg_buttonFontWeight = 400;
                root.cfg_buttonFontStyleName = "";
            }
        }
    }

    RowLayout {
        Kirigami.FormData.label: i18n("Font size:")
        visible: showButtonTextCheckBox.checked

        QQC2.SpinBox {
            id: fontSizeSpinBox
            from: 0
            to: 72
            value: root.cfg_buttonFontSize
            textFromValue: (val) => val === 0 ? i18n("Default") : val + " pt"
            valueFromText: (str) => {
                const n = parseInt(str);
                return isNaN(n) ? 0 : n;
            }
            onValueModified: root.cfg_buttonFontSize = value
        }
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Overview Behavior")
    }

    QQC2.CheckBox {
        id: showWorkspaceStripCheckBox
        Kirigami.FormData.label: i18n("Pager:")
        text: i18n("Show virtual desktops pager bar at top")
    }

    QQC2.CheckBox {
        id: showCloseButtonsCheckBox
        Kirigami.FormData.label: i18n("Window Cards:")
        text: i18n("Show close button on window cards")
    }

    QQC2.CheckBox {
        id: hasBottomPanelCheckBox
        Kirigami.FormData.label: i18n("Layout:")
        text: i18n("Add bottom margin for bottom panel")
    }
}
