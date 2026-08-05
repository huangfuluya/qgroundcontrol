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
// 左侧：紧凑状态条（6项指示器）+ 控制面板（镜头切换 | 回中〇 | 拍照/录像 | 变焦(+)/(-) | 夜视/补光 | 预留）
// 右侧：竖排操作列（直线返航/原路返航 + 手动/自动/抛锚模式切换）+ 大号圆形解锁/锁定按钮
// 配色：室外高对比深色风格（深黑底 + 白色粗体字），仅解锁/锁定使用红绿配色

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
    property bool  _showingSecondVideo:    false ///< Video source 1/2 toggle state

    //-- Outdoor high-contrast color scheme
    readonly property color _cPanelBg:      Qt.rgba(0, 0, 0, 0.75)      ///< Panel background
    readonly property color _cPanelBorder:  Qt.rgba(1, 1, 1, 0.3)       ///< Panel border
    readonly property color _cBtnBg:        "#2E2E2E"                   ///< Normal button background
    readonly property color _cBtnText:      "#FFFFFF"                   ///< Normal button text
    readonly property color _cValueText:    "#7CFC9B"                   ///< Status value / active-state green
    readonly property color _cActiveBg:     "#1E4620"                   ///< Toggle-ON / current-mode background
    readonly property color _cLabelText:    "#AAAAAA"                   ///< Status label text
    readonly property color _cArmColor:     "#2E7D32"                   ///< Arm (unlock) green
    readonly property color _cDisarmColor:  "#C62828"                   ///< Disarm (lock) red
    readonly property real _cBtnW:          ScreenTools.defaultFontPixelWidth * 10  ///< Button cell width
    readonly property real _cBtnH:          ScreenTools.defaultFontPixelHeight * 2.6  ///< Button cell height
    readonly property real _leftPanelContentH: (_cBtnH * 1.0) + (_cBtnH * 1.4) + (4 * _cBtnH) + (5 * _margins / 2)

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
            anchors.left:           leftPanel.right
            anchors.bottom:         parent.bottom
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
        color:                  _cPanelBg
        border.color:           _cPanelBorder
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
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           _activeVehicle ? _activeVehicle.flightMode : "--"
                    font.pointSize: ScreenTools.smallFontPointSize
                    font.bold:      true
                    color:          _cValueText
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
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.groundSpeed && _activeVehicle.groundSpeed.value !== undefined) ? _activeVehicle.groundSpeed.value.toFixed(1) : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          _cValueText
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
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.heading && _activeVehicle.heading.value !== undefined) ? _activeVehicle.heading.value.toFixed(0) + "°" : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          _cValueText
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }

            // Voltage
            ColumnLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing:         0
                QGCLabel {
                    text:           qsTr("电压")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text: {
                        if (!_activeVehicle || !_activeVehicle.batteries || _activeVehicle.batteries.count === 0) return "--V"
                        var battery = _activeVehicle.batteries.get(0)
                        if (!battery || !battery.voltage || isNaN(battery.voltage.rawValue)) return "--V"
                        return battery.voltage.valueString + battery.voltage.units
                    }
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color: {
                        if (!_activeVehicle || !_activeVehicle.batteries || _activeVehicle.batteries.count === 0) return _cLabelText
                        var battery = _activeVehicle.batteries.get(0)
                        if (!battery || !battery.voltage || isNaN(battery.voltage.rawValue)) return _cLabelText
                        // Use percentRemaining for color if available, otherwise green
                        if (battery.percentRemaining && !isNaN(battery.percentRemaining.rawValue)) {
                            var pct = battery.percentRemaining.rawValue
                            if (pct < 20) return "red"
                            if (pct < 50) return "orange"
                        }
                        return _cValueText
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
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                QGCLabel {
                    text:           (_activeVehicle && _activeVehicle.rangeFinderDist && _activeVehicle.rangeFinderDist.value !== undefined) ? _activeVehicle.rangeFinderDist.value.toFixed(1) + "m" : "--"
                    font.pointSize: ScreenTools.defaultFontPointSize
                    font.bold:      true
                    color:          _cValueText
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
                    color:          _cLabelText
                    Layout.alignment: Qt.AlignHCenter
                }
                Rectangle {
                    width:  ScreenTools.defaultFontPixelHeight * 1.2
                    height: width
                    radius: width / 2
                    color:  _activeVehicle ? (_activeVehicle.armed ? _cArmColor : _cDisarmColor) : _cDisarmColor
                    Layout.alignment: Qt.AlignHCenter
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    //-- Left Side: Camera/PTZ Control Panel (to the right of status strip)
    //   Row 1: 镜头切换 | Row 2: 回中 ○ | Rows 3-6: 2-column grid
    Rectangle {
        id:                     leftPanel
        anchors.left:           leftStrip.right
        anchors.leftMargin:     _margins / 2
        anchors.verticalCenter: parent.verticalCenter
        width:                  _cBtnW * 2 + _margins * 1.5
        height:                 _leftPanelContentH + _margins + _cBtnH * 0.5
        color:                  _cPanelBg
        border.color:           _cPanelBorder
        radius:                 4
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id:                 leftLayout
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.margins:    _margins / 2
            spacing:            _margins / 2

            //-- Row 1: 镜头切换 (Video source 1 / 2 toggle)
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: _cBtnH
                text:                   qsTr("镜头切换")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                textColor:              _cBtnText
                enabled:                QGroundControl.videoManager.hasVideo2
                backgroundColor:        _cBtnBg
                onClicked: {
                    _showingSecondVideo = !_showingSecondVideo
                    QGroundControl.videoManager.setSecondVideoActive(_showingSecondVideo)
                }
            }

            //-- Row 2: 回中 (circular, centered)
            Rectangle {
                Layout.alignment:           Qt.AlignHCenter
                Layout.preferredWidth:      _cBtnH * 1.4
                Layout.preferredHeight:     Layout.preferredWidth
                radius:                     Layout.preferredWidth / 2
                color:                      _cBtnBg
                border.color:               _cValueText
                border.width:               2

                DeadMouseArea { anchors.fill: parent }

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               qsTr("回中")
                    font.pointSize:     ScreenTools.largeFontPointSize
                    font.bold:          true
                    color:              _cBtnText
                }

                MouseArea {
                    anchors.fill:   parent
                    enabled:        _activeVehicle !== null
                    onClicked: {
                        if (_activeVehicle) {
                            _activeVehicle.sendCommand(1, 205, false, 0, 0, 0, 0, 0, 0, 1)
                        }
                    }
                }
            }

            //-- Rows 3-6: 2-column grid (拍照/录像 | 变焦(+)/变焦(-) | 夜视/补光 | 预留/预留)
            // Row 3: 拍照 | 录像
            RowLayout {
                Layout.fillWidth:       true
                Layout.preferredHeight: _cBtnH
                spacing:                _margins / 2
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   qsTr("拍照")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _servoPulseChannel = 10
                            _activeVehicle.sendCommand(1, 183, false, 10, 2000, 0, 0, 0, 0, 0)
                        }
                    }
                }
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   qsTr("录像")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _servoPulseChannel = 10
                            _activeVehicle.sendCommand(1, 183, false, 10, 1000, 0, 0, 0, 0, 0)
                        }
                    }
                }
            }

            // Row 4: 变焦(+) | 变焦(-)
            RowLayout {
                Layout.fillWidth:       true
                Layout.preferredHeight: _cBtnH
                spacing:                _margins / 2
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   qsTr("变焦(+)")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _activeVehicle.sendCommand(1, 183, false, 9, 1000, 0, 0, 0, 0, 0)
                            _zoomPulseChannel = 9
                            zoomResetTimer.restart()
                        }
                    }
                }
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   qsTr("变焦(-)")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _activeVehicle.sendCommand(1, 183, false, 9, 2000, 0, 0, 0, 0, 0)
                            _zoomPulseChannel = 9
                            zoomResetTimer.restart()
                        }
                    }
                }
            }

            // Row 5: 夜视 | 补光
            RowLayout {
                Layout.fillWidth:       true
                Layout.preferredHeight: _cBtnH
                spacing:                _margins / 2
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   _nightVisionOn ? qsTr("夜视·开") : qsTr("夜视·关")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _nightVisionOn ? _cValueText : _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _nightVisionOn ? _cActiveBg : _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _nightVisionOn = !_nightVisionOn
                            var pwm = _nightVisionOn ? 2000 : 1000
                            _activeVehicle.sendCommand(1, 183, false, 11, pwm, 0, 0, 0, 0, 0)
                        }
                    }
                }
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   _fillLightOn ? qsTr("补光·开") : qsTr("补光·关")
                    pointSize:              ScreenTools.defaultFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _fillLightOn ? _cValueText : _cBtnText
                    enabled:                _activeVehicle !== null
                    backgroundColor:        _fillLightOn ? _cActiveBg : _cBtnBg
                    onClicked: {
                        if (_activeVehicle) {
                            _fillLightOn = !_fillLightOn
                            var pwm = _fillLightOn ? 2000 : 1000
                            _activeVehicle.sendCommand(1, 183, false, 12, pwm, 0, 0, 0, 0, 0)
                        }
                    }
                }
            }

            // Row 6: 预留按钮1 | 预留按钮2
            RowLayout {
                Layout.fillWidth:       true
                Layout.preferredHeight: _cBtnH
                spacing:                _margins / 2
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   "—"
                    pointSize:              ScreenTools.smallFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cLabelText
                    enabled:                false
                    backgroundColor:        _cBtnBg
                }
                QGCButton {
                    Layout.preferredWidth:  _cBtnW
                    Layout.preferredHeight: _cBtnH
                    text:                   "—"
                    pointSize:              ScreenTools.smallFontPointSize
                    fontWeight:             Font.Bold
                    showBorder:             true
                    textColor:              _cLabelText
                    enabled:                false
                    backgroundColor:        _cBtnBg
                }
            }
        }
    }

    //-- Right Side: Vertical Action Column (RTL buttons + mode switches + arm circle)
    Item {
        id:                     rightPanel
        anchors.top:            parent.top
        anchors.topMargin:      parent.height * 0.12
        anchors.bottom:         parent.bottom
        anchors.bottomMargin:   _margins
        anchors.right:          parent.right
        anchors.rightMargin:    _margins
        width:                  ScreenTools.defaultFontPixelWidth * 16
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill:   parent
            spacing:        _margins

            // RTL
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 4
                text:                   qsTr("直线返航")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                textColor:              _cBtnText
                enabled:                _activeVehicle !== null
                backgroundColor:        _cPanelBg
                onClicked: { if (_activeVehicle) confirmRTLDialog.open() }
            }

            // Smart RTL
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 4
                text:                   qsTr("原路返航")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                textColor:              _cBtnText
                enabled:                _activeVehicle !== null
                backgroundColor:        _cPanelBg
                onClicked: { if (_activeVehicle) confirmSmartRTLDialog.open() }
            }

            // Separator
            Rectangle {
                Layout.fillWidth:   true
                Layout.preferredHeight: 1
                color:              Qt.rgba(1, 1, 1, 0.2)
            }

            // Manual Mode
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 4
                text:                   qsTr("手动模式")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                enabled:                _activeVehicle !== null
                textColor:              _activeVehicle && _activeVehicle.flightMode === "Manual" ? _cValueText : _cBtnText
                backgroundColor:        _activeVehicle && _activeVehicle.flightMode === "Manual" ? _cActiveBg : _cPanelBg
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Manual" }
            }

            // Auto Mode
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 4
                text:                   qsTr("自动模式")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                enabled:                _activeVehicle !== null
                textColor:              _activeVehicle && _activeVehicle.flightMode === "Auto" ? _cValueText : _cBtnText
                backgroundColor:        _activeVehicle && _activeVehicle.flightMode === "Auto" ? _cActiveBg : _cPanelBg
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Auto" }
            }

            // Loiter (Anchor) Mode
            QGCButton {
                Layout.fillWidth:       true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 4
                text:                   qsTr("抛锚模式")
                pointSize:              ScreenTools.largeFontPointSize
                fontWeight:             Font.Bold
                showBorder:             true
                enabled:                _activeVehicle !== null
                textColor:              _activeVehicle && _activeVehicle.flightMode === "Loiter" ? _cValueText : _cBtnText
                backgroundColor:        _activeVehicle && _activeVehicle.flightMode === "Loiter" ? _cActiveBg : _cPanelBg
                onClicked: { if (_activeVehicle) _activeVehicle.flightMode = "Loiter" }
            }

            Item { Layout.fillHeight: true }

            // Arm/Disarm Circular Button (special red/green color)
            Rectangle {
                Layout.alignment:       Qt.AlignHCenter
                Layout.preferredWidth:  ScreenTools.defaultFontPixelHeight * 6
                Layout.preferredHeight: Layout.preferredWidth
                radius:                 Layout.preferredWidth / 2
                color:                  _activeVehicle && _activeVehicle.armed ? _cDisarmColor : _cArmColor
                border.color:           Qt.rgba(1, 1, 1, 0.5)
                border.width:           2
                opacity:                _activeVehicle !== null ? 1 : 0.4

                QGCLabel {
                    anchors.centerIn:   parent
                    text:               _activeVehicle && _activeVehicle.armed ? qsTr("锁定") : qsTr("解锁")
                    font.pointSize:     ScreenTools.largeFontPointSize
                    font.bold:          true
                    color:              _cBtnText
                }

                MouseArea {
                    anchors.fill:   parent
                    enabled:        _activeVehicle !== null
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
        }
    }

    //-- Confirmation Dialogs
    MessageDialog {
        id:         confirmRTLDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要执行直线返航吗？\n无人船将切换到RTL模式，直线返回返航点。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.guidedModeRTL(false) }
        }
    }

    MessageDialog {
        id:         confirmSmartRTLDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要执行原路返航吗？\n无人船将切换到Smart RTL模式，沿原路径返回返航点。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes && _activeVehicle) { _activeVehicle.guidedModeRTL(true) }
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
        width:                  ScreenTools.defaultFontPixelWidth * 18
        height:                 ScreenTools.defaultFontPixelHeight * 3
        color:                  _cPanelBg
        radius:                 4
        border.color:           _cPanelBorder
        border.width:           1
        visible:                !QGroundControl.videoManager.fullScreen

        DeadMouseArea {
            anchors.fill: parent
        }

        RowLayout {
            anchors.fill:       parent
            anchors.margins:    _margins / 2
            spacing:            _margins / 2

            QGCLabel {
                Layout.alignment:   Qt.AlignVCenter
                text:               qsTr("高级模式")
                font.pointSize:     ScreenTools.defaultFontPointSize
                font.bold:          true
                color:              _cBtnText
            }

            Item { Layout.fillWidth: true }

            QGCSwitch {
                id:                 modeSwitch
                Layout.alignment:   Qt.AlignVCenter
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
