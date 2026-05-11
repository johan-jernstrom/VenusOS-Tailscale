import QtQuick
import Victron.VenusOS

Page {
    id: root
    title: qsTr("Tailscale")

    GradientListView {
        model: VisibleItemModel {

            ListSwitch {
                id: enableSwitch
                text: qsTr("Enable Tailscale")
                dataItem.uid: "dbus/com.victronenergy.settings/Settings/Tailscale/Enabled"
                writeAccessLevel: VenusOS.User_AccessType_User
            }

            ListText {
                text: qsTr("Status")
                dataItem.uid: "dbus/com.victronenergy.tailscale/StateText"
                secondaryText: dataItem.valid ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.valid && enableSwitch.dataItem.value
            }

            ListText {
                text: qsTr("IPv4 Address")
                dataItem.uid: "dbus/com.victronenergy.tailscale/Ip4"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListText {
                text: qsTr("IPv6 Address")
                dataItem.uid: "dbus/com.victronenergy.tailscale/Ip6"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListText {
                text: qsTr("Hostname")
                dataItem.uid: "dbus/com.victronenergy.tailscale/HostName"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListText {
                text: qsTr("Tailnet")
                dataItem.uid: "dbus/com.victronenergy.tailscale/TailnetName"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListText {
                text: qsTr("Key Expiry")
                dataItem.uid: "dbus/com.victronenergy.tailscale/KeyExpiry"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListText {
                text: qsTr("Login Link")
                dataItem.uid: "dbus/com.victronenergy.tailscale/LoginLink"
                secondaryText: dataItem.valid && dataItem.value !== "" ? dataItem.value : "--"
                preferredVisible: enableSwitch.dataItem.value
                    && dataItem.valid && dataItem.value !== ""
            }

            ListTextField {
                text: qsTr("Auth Key")
                dataItem.uid: "dbus/com.victronenergy.settings/Settings/Tailscale/AuthKey"
                textField.maximumLength: 200
                writeAccessLevel: VenusOS.User_AccessType_User
                preferredVisible: enableSwitch.dataItem.value
            }

            ListSwitch {
                text: qsTr("Advertise Exit Node")
                dataItem.uid: "dbus/com.victronenergy.settings/Settings/Tailscale/AdvertiseExitNode"
                writeAccessLevel: VenusOS.User_AccessType_User
                preferredVisible: enableSwitch.dataItem.value
            }

            ListSwitch {
                text: qsTr("Accept Routes")
                dataItem.uid: "dbus/com.victronenergy.settings/Settings/Tailscale/AcceptRoutes"
                writeAccessLevel: VenusOS.User_AccessType_User
                preferredVisible: enableSwitch.dataItem.value
            }

            ListTextField {
                text: qsTr("Custom Login Server")
                dataItem.uid: "dbus/com.victronenergy.settings/Settings/Tailscale/LoginServer"
                textField.maximumLength: 255
                writeAccessLevel: VenusOS.User_AccessType_User
                preferredVisible: enableSwitch.dataItem.value
            }
        }
    }
}
