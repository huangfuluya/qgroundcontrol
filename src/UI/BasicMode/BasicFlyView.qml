/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// 航行监控 - Navigation Monitor Tab
// 主视图支持地图/视频双窗口切换，并保留基础模式的状态与操作叠加层
// 左侧：紧凑状态条（6项指示器）+ 云台控制按钮面板（3行x2列，拍照/录像/变焦远/变焦近/夜视/补光）+ 圆形回中按钮
// 右侧：快捷操作按钮（3个）
// 底部：快捷模式切换按钮（4个，水平平铺）

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controllers
import QGroundControl.Controls
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

Item {
    id: _root

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property real   _margins:               ScreenTools.defaultFontPixelWidth
    property bool   _isFullWindowItemDark:  true
    property var    _guidedController:      guidedActionsController
    property var    planController:         _planController
    property var    guidedController:       guidedActionsController
    property real   _pipMargin:             ScreenTools.defaultFontPixelWidth * 0.75
    //-- Servo/PWM control state
    property int   _servoPulseChannel:     -1    ///< Channel waiting for reset pulse
    property bool  _nightVisionOn:         false ///< Night vision toggle state
    property bool  _fillLightOn:           false ///< Fill light toggle state
    property int   _zoomPulseChannel:      -1    ///< Zoom channel, no ack wait

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    // Required for map click "Go to Location" functionality
    GuidedActionsController {
        id:                 guidedActionsController
        missionController:  _missionController
        guidedValueSlider:  guidedValueSlider
        // Explicitly wire confirmDialog after all children are created
        Component.onCompleted: confirmDialog = guidedActionConfirm
    }

    Item {
        id:                 mainView
        anchors.fill:       parent

        FlyViewMap {
            id:                     mapControl
            anchors.fill:           parent
            planMasterController:   _planController
            guidedController:       guidedActionsController
            pipView:                _pipView
            pipMode:                videoControl.pipState.state === videoControl.pipState.fullState
            mapName:                "BasicModeFlyView"
        }

        FlyViewVideo {
            id:         videoControl
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            anchors.left:           servoPanel.right
            anchors.bottom:         quickModeBar.top
            anchors.margins:        _pipMargin
            item1IsFullSettingsKey: "BasicModeMainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState || mapControl.pipState.state === mapControl.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets
        }
    }

    //-- Left Side: Compact Status Strip (overlay on map)
    Rectangle {
        id:                     leftStrip
        anchors.top:            parent.top
        anchors.bottom:         parent.bottom
        anchors.left:           parent.left
        width:                  ScreenTools.defaultFontPixelWidth * 8
        color:                  Qt.rgba(0, 0, 0, 0.55)
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill:       parent
            anchors.margins:    2
            spacing:            2

            // Current Mode
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("模式")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           _activeVehicle ? _activeVehicle.flightMode : "--"
                    font.pointSize: ScreenTools.smallFontPointSize
                    font.bold:      true
                    color:          qgcPal.colorGreen
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Speed
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("航速")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.groundSpeed && _activeVehicle.groundSpeed.value !== undefined) ? _activeVehicle.groundSpeed.value.toFixed(1) : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          qgcPal.colorGreen
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Heading
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("航向")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.heading && _activeVehicle.heading.value !== undefined) ? _activeVehicle.heading.value.toFixed(0) + "°" : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          qgcPal.colorGreen
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Battery
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("电量")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.batteryPercent && _activeVehicle.batteryPercent.value !== undefined) ? _activeVehicle.batteryPercent.value.toFixed(0) + "%" : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color: {
                        if (!_activeVehicle || !_activeVehicle.batteryPercent || _activeVehicle.batteryPercent.value === undefined) return "#AAAAAA"
                        var pct = _activeVehicle.batteryPercent.value
                        if (pct < 20) return "red"
                        if (pct < 50) return "orange"
                        return qgcPal.colorGreen
                    }
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Depth
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("水深")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.rangeFinderDist && _activeVehicle.rangeFinderDist.value !== undefined) ? _activeVehicle.rangeFinderDist.value.toFixed(1) + "m" : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          qgcPal.colorGreen
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Arm Status
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("解锁")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    width:  ScreenTools.defaultFontPixelHeight * 1.2
                    height: width
                    radius: width / 2
                    color:  _activeVehicle ? (_activeVehicle.armed ? qgcPal.colorGreen : "red") : "red"
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    //-- Left Side: Servo/PWM Control Buttons (3x2 grid, to the right of status strip)
    Rectangle {
        id:                     servoPanel
        anchors.left:           leftStrip.right
        anchors.leftMargin:     _margins / 2
        anchors.bottom:         quickModeBar.top
        anchors.bottomMargin:   _margins
        width:                  ScreenTools.defaultFontPixelWidth * 20
        height:                 ScreenTools.defaultFontPixelHeight * 22
        color:                  Qt.rgba(0, 0, 0, 0.55)
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        radius:                 4
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        GridLayout {
            anchors.margins:    _margins / 2
            anchors.fill:       parent
            columns:            2
            rows:               3
            columnSpacing:      _margins / 2
            rowSpacing:         _margins / 2

            // Row 1, Col 1: Photo
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               qsTr("拍照")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    "#4A90D9"
                onClicked: {
                    if (_activeVehicle) {
                        _servoPulseChannel = 10
                        _activeVehicle.sendCommand(1, 183, false, 10, 2000, 0, 0, 0, 0, 0)
                    }
                }
            }

            // Row 1, Col 2: Video
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               qsTr("录像")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    "#4A90D9"
                onClicked: {
                    if (_activeVehicle) {
                        _servoPulseChannel = 10
                        _activeVehicle.sendCommand(1, 183, false, 10, 1000, 0, 0, 0, 0, 0)
                    }
                }
            }

            // Row 2, Col 1: Zoom Tele (no ack wait)
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               qsTr("变焦远")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    "#4A90D9"
                onClicked: {
                    if (_activeVehicle) {
                        _activeVehicle.sendCommand(1, 183, false, 9, 1000, 0, 0, 0, 0, 0)
                        _zoomPulseChannel = 9
                        zoomResetTimer.restart()
                    }
                }
            }

            // Row 2, Col 2: Zoom Wide (no ack wait)
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               qsTr("变焦近")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    "#4A90D9"
                onClicked: {
                    if (_activeVehicle) {
                        _activeVehicle.sendCommand(1, 183, false, 9, 2000, 0, 0, 0, 0, 0)
                        _zoomPulseChannel = 9
                        zoomResetTimer.restart()
                    }
                }
            }

            // Row 3, Col 1: Night Vision (toggle)
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               _nightVisionOn ? qsTr("夜视·开") : qsTr("夜视·关")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    _nightVisionOn ? "#4A90D9" : "#2C5F8A"
                onClicked: {
                    if (_activeVehicle) {
                        _nightVisionOn = !_nightVisionOn
                        var pwm = _nightVisionOn ? 2000 : 1000
                        _activeVehicle.sendCommand(1, 183, false, 11, pwm, 0, 0, 0, 0, 0)
                    }
                }
            }

            // Row 3, Col 2: Fill Light (toggle)
            QGCButton {
                Layout.fillWidth:   true
                Layout.fillHeight:  true
                text:               _fillLightOn ? qsTr("补光·开") : qsTr("补光·关")
                font.pointSize:     ScreenTools.defaultFontPointSize
                enabled:            _activeVehicle !== null
                opacity:            0.5
                backgroundColor:    _fillLightOn ? "#4A90D9" : "#2C5F8A"
                onClicked: {
                    if (_activeVehicle) {
                        _fillLightOn = !_fillLightOn
                        var pwm = _fillLightOn ? 2000 : 1000
                        _activeVehicle.sendCommand(1, 183, false, 12, pwm, 0, 0, 0, 0, 0)
                    }
                }
            }
        }
    }

    //-- Camera Centering Button (circular, below servo panel)
    Rectangle {
        id:                     centerButton
        anchors.top:            servoPanel.bottom
        anchors.topMargin:      _margins / 2
        anchors.horizontalCenter: servoPanel.horizontalCenter
        width:                  ScreenTools.defaultFontPixelHeight * 5
        height:                 width
        radius:                 width / 2
        color:                  "#4A90D9"
        opacity:                0.5
        visible:                !QGroundControl.videoManager.fullScreen
        border.color:           Qt.rgba(1, 1, 1, 0.3)

        DeadMouseArea {
            anchors.fill: parent
        }

        QGCLabel {
            anchors.centerIn:   parent
            text:               qsTr("回中")
            font.pointSize:     ScreenTools.defaultFontPointSize
            color:              "white"
        }

        MouseArea {
            anchors.fill: parent
            enabled: _activeVehicle !== null
            onClicked: {
                if (_activeVehicle) {
                    _activeVehicle.sendCommand(1, 205, false, 0, 0, 0, 0, 0, 0, 1)
                }
            }
        }
    }


    //-- Right Side: Action Buttons (individual floating items)
    Rectangle {
        id:                     btnRTL
        anchors.top:            parent.top
        anchors.topMargin:      parent.height * 0.15
        anchors.right:          parent.right
        anchors.rightMargin:    _margins
        width:                  ScreenTools.defaultFontPixelWidth * 16
        height:                 ScreenTools.defaultFontPixelHeight * 4
        color:                  Qt.rgba(0, 0, 0, 0.55)
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        radius:                 4
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        QGCButton {
            anchors.fill:       parent
            text:               qsTr("一键返航")
            font.pointSize:     ScreenTools.largeFontPointSize
            enabled:            _activeVehicle !== null
            backgroundColor:    "#E74C3C"
            onClicked: { if (_activeVehicle) confirmRTLDialog.open() }
        }
    }

    Rectangle {
        id:                     btnStop
        anchors.top:            btnRTL.bottom
        anchors.topMargin:      _margins
        anchors.right:          parent.right
        anchors.rightMargin:    _margins
        width:                  ScreenTools.defaultFontPixelWidth * 16
        height:                 ScreenTools.defaultFontPixelHeight * 4
        color:                  Qt.rgba(0, 0, 0, 0.55)
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        radius:                 4
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        QGCButton {
            anchors.fill:       parent
            text:               qsTr("紧急停船")
            font.pointSize:     ScreenTools.largeFontPointSize
            enabled:            _activeVehicle !== null
            backgroundColor:    "#C0392B"
            onClicked: { if (_activeVehicle) confirmStopDialog.open() }
        }
    }

    Rectangle {
        id:                     btnArm
        anchors.top:            btnStop.bottom
        anchors.topMargin:      _margins
        anchors.right:          parent.right
        anchors.rightMargin:    _margins
        width:                  ScreenTools.defaultFontPixelWidth * 16
        height:                 ScreenTools.defaultFontPixelHeight * 4
        color:                  Qt.rgba(0, 0, 0, 0.55)
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        radius:                 4
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        QGCButton {
            anchors.fill:       parent
            text:               _activeVehicle ? (_activeVehicle.armed ? qsTr("锁定") : qsTr("解锁")) : qsTr("解锁")
            font.pointSize:     ScreenTools.largeFontPointSize
            enabled:            _activeVehicle !== null
            backgroundColor:    _activeVehicle ? (_activeVehicle.armed ? "#E6A817" : "#27AE60") : "gray"
            onClicked: {
                if (_activeVehicle) {
                    if (_activeVehicle.armed) {
                        confirmDisarmDialog.open()
                    } else {
                        confirmArmDialog.open()
                    }
                }
            }
        }
    }

    //-- Bottom: Quick Mode Switch Buttons (overlay, horizontal)
    Rectangle {
        id:                         quickModeBar
        anchors.bottom:             parent.bottom
        anchors.bottomMargin:       _margins
        anchors.horizontalCenter:   parent.horizontalCenter
        width:                      ScreenTools.defaultFontPixelWidth * 62
        height:                     ScreenTools.defaultFontPixelHeight * 5
        color:                      Qt.rgba(0, 0, 0, 0.6)
        border.color:               Qt.rgba(1, 1, 1, 0.15)
        radius:                     4
        visible:                    !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        RowLayout {
            anchors.centerIn:   parent
            spacing:            _margins * 1.5

            QGCButton {
                text:               qsTr("手动模式")
                font.pointSize:     ScreenTools.defaultFontPointSize
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 13
                enabled:            _activeVehicle !== null && _activeVehicle.flightMode !== "Manual"
                backgroundColor:    "#4A90D9"
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Manual" }
            }
            QGCButton {
                text:               qsTr("悬停模式")
                font.pointSize:     ScreenTools.defaultFontPointSize
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 13
                enabled:            _activeVehicle !== null && _activeVehicle.flightMode !== "Loiter"
                backgroundColor:    "#4A90D9"
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Loiter" }
            }
            QGCButton {
                text:               qsTr("保持模式")
                font.pointSize:     ScreenTools.defaultFontPointSize
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 13
                enabled:            _activeVehicle !== null && _activeVehicle.flightMode !== "Hold"
                backgroundColor:    "#4A90D9"
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Hold" }
            }
            QGCButton {
                text:               qsTr("自动模式")
                font.pointSize:     ScreenTools.defaultFontPointSize
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
                Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 13
                enabled:            _activeVehicle !== null && _activeVehicle.flightMode !== "Auto"
                backgroundColor:    "#4A90D9"
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Auto" }
            }
        }
    }

    //-- Confirmation Dialogs
    MessageDialog {
        id:         confirmRTLDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要执行一键返航吗？\n无人船将立即返回预设的返航点。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.guidedModeRTL() }
        }
    }

    MessageDialog {
        id:         confirmStopDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要紧急停船吗？\n无人船将立即切换到保持模式并原地待命。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.flightMode = "Hold" }
        }
    }

    MessageDialog {
        id:         confirmArmDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要解锁吗？\n解锁后电机将开始旋转，请确保周围安全。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.armed = true }
        }
    }

    MessageDialog {
        id:         confirmDisarmDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要锁定吗？\n锁定后电机将停止旋转。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.armed = false }
        }
    }

    //-- Advanced Mode Switch (overlay, top-right)
    Rectangle {
        anchors.top:            parent.top
        anchors.topMargin:      _margins
        anchors.right:          parent.right
        anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 18
        width:                  ScreenTools.defaultFontPixelWidth * 14
        height:                 ScreenTools.defaultFontPixelHeight * 3.5
        color:                  Qt.rgba(0, 0, 0, 0.5)
        radius:                 4
        border.color:           Qt.rgba(1, 1, 1, 0.15)
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        RowLayout {
            anchors.centerIn:   parent
            spacing:            _margins / 2
            QGCLabel {
                text:           qsTr("高级模式")
                font.pointSize: ScreenTools.smallFontPointSize
                color:          "#AAAAAA"
            }
            QGCSwitch {
                id:                 modeSwitch
                checked:            false
                onCheckedChanged: {
                    if (checked) { advancedModeConfirmation.open() }
                }
            }
        }
    }

    MessageDialog {
        id:         advancedModeConfirmation
        title:      qsTr("切换至高级模式")
        text:       QGroundControl.corePlugin.showAdvancedUIMessage
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                QGroundControl.corePlugin.showAdvancedUI = true
            } else {
                modeSwitch.checked = false
            }
        }
    }

    Connections {
        target: QGroundControl.corePlugin
        function onShowAdvancedUIChanged(show) { modeSwitch.checked = show }
    }

    //-- Zoom pulse reset timer (fires 0.5s after command, no ack wait)
    Timer {
        id:         zoomResetTimer
        interval:   500
        repeat:     false
        onTriggered: {
            if (_activeVehicle && _zoomPulseChannel > 0) {
                var ch = _zoomPulseChannel
                _zoomPulseChannel = -1
                _activeVehicle.sendCommand(1, 183, false, ch, 1500, 0, 0, 0, 0, 0)
            }
        }
    }

    //-- Servo pulse reset timer (fires 1s after successful command ack)
    Timer {
        id:         servoResetTimer
        interval:   1000
        repeat:     false
        onTriggered: {
            if (_activeVehicle && _servoPulseChannel > 0) {
                var ch = _servoPulseChannel
                _servoPulseChannel = -1
                _activeVehicle.sendCommand(1, 183, false, ch, 1500, 0, 0, 0, 0, 0)
            }
        }
    }

    //-- Listen for MAVLink command acknowledgements
    Connections {
        target: _activeVehicle
        function onMavCommandResult(vehicleId, comp, cmd, result, code) {
            // MAV_CMD_DO_SET_SERVO (183): if pulse command succeeded, start reset timer
            if (cmd === 183 && result === 0 /* MAV_RESULT_ACCEPTED */ && _servoPulseChannel > 0) {
                servoResetTimer.start()
            }
        }
    }


    // Guided value slider (required for actions that need slider input)
    // Declared after all overlays to ensure it renders on top
    GuidedValueSlider {
        id:                     guidedValueSlider
        anchors.bottom:         parent.bottom
        anchors.left:           parent.left
        anchors.right:          parent.right
        z:                      QGroundControl.zOrderTopMost
    }

    // Guided action confirmation dialog (required for guided mode interactions)
    // Declared last to ensure it renders above all overlays in basic mode
    GuidedActionConfirm {
        id:                     guidedActionConfirm
        anchors.centerIn:       parent
        z:                      QGroundControl.zOrderTopMost
        guidedController:       guidedActionsController
        guidedValueSlider:      guidedValueSlider
    }
}
