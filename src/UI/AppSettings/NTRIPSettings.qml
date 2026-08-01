/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.FactSystem
import QGroundControl.FactControls
import QGroundControl.Controls
import QGroundControl.ScreenTools
import QGroundControl.Palette

SettingsPage {
    property var    _settingsManager:   QGroundControl.settingsManager
    property var    _ntripSettings:     _settingsManager.ntripSettings
    property Fact   _enabled:           _ntripSettings.ntripServerConnectEnabled
    property var    _ntripManager:      QGroundControl.ntripManager
    property QGCPalette qgcPal:         QGroundControl.globalPalette

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("NTRIP / RTK")
        visible:            _ntripSettings.visible

        FactCheckBoxSlider {
            Layout.fillWidth:   true
            text:               _enabled.shortDescription
            fact:               _enabled
            visible:            _enabled.visible
        }

        QGCLabel {
            Layout.fillWidth:   true
            wrapMode:           Text.WordWrap
            visible:            _enabled.rawValue
            text:               _ntripManager ? _ntripManager.ntripStatus : qsTr("NTRIP not available")
            color:              {
                if (!_ntripManager) {
                    return qgcPal.text
                }
                if (_ntripManager.connected) {
                    return qgcPal.colorGreen
                }
                var status = _ntripManager.ntripStatus.toLowerCase()
                if (status.indexOf("error") >= 0) {
                    return qgcPal.colorRed
                }
                return qgcPal.colorOrange
            }
        }
    }

    SettingsGroupLayout {
        Layout.fillWidth:   true
        heading:            qsTr("Server")
        visible:            _ntripSettings.visible

        LabelledFactTextField {
            label:                  _ntripSettings.ntripServerHostAddress.shortDescription
            fact:                   _ntripSettings.ntripServerHostAddress
            visible:                _ntripSettings.ntripServerHostAddress.visible
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 40
        }

        LabelledFactTextField {
            label:                  _ntripSettings.ntripServerPort.shortDescription
            fact:                   _ntripSettings.ntripServerPort
            visible:                _ntripSettings.ntripServerPort.visible
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 10
        }

        LabelledFactTextField {
            label:                  _ntripSettings.ntripUsername.shortDescription
            fact:                   _ntripSettings.ntripUsername
            visible:                _ntripSettings.ntripUsername.visible
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 30
        }

        LabelledFactTextField {
            label:                  _ntripSettings.ntripPassword.shortDescription
            fact:                   _ntripSettings.ntripPassword
            visible:                _ntripSettings.ntripPassword.visible
            textField.echoMode:     TextInput.Password
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 30
        }

        LabelledFactTextField {
            label:                  _ntripSettings.ntripMountpoint.shortDescription
            fact:                   _ntripSettings.ntripMountpoint
            visible:                _ntripSettings.ntripMountpoint.visible
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 30
        }

        LabelledFactTextField {
            label:                  _ntripSettings.ntripWhitelist.shortDescription
            fact:                   _ntripSettings.ntripWhitelist
            visible:                _ntripSettings.ntripWhitelist.visible
            textFieldPreferredWidth: ScreenTools.defaultFontPixelWidth * 40
        }
    }
}
