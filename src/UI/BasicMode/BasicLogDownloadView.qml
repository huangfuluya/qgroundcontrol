/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// 日志下载 - Log Download Tab
// Left: Onboard logs (板载日志)
// Right: Telemetry logs (遥测日志)

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Vehicle

Item {
    id: _root

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property real   _margins:           ScreenTools.defaultFontPixelWidth
    property bool   _hasVehicle:        _activeVehicle !== null && !_activeVehicle.isOfflineEditingVehicle
    property string _statusMessage:     ""
    property int    _prevModelCount:    0

    Timer {
        id:             _requestTimeout
        interval:       10000
        repeat:         false
        onTriggered: {
            if (logDownloadController.model.count === _prevModelCount) {
                _statusMessage = qsTr("飞控未响应，可能不支持日志下载")
            }
        }
    }

    Timer {
        id:             _modelCheckTimer
        interval:       500
        running:        _prevModelCount > 0 && _statusMessage !== ""
        repeat:         true
        onTriggered: {
            if (logDownloadController.model.count > _prevModelCount) {
                _requestTimeout.stop()
                _statusMessage = ""
                _prevModelCount = 0
            }
        }
    }

    function _doRefresh() {
        _prevModelCount = logDownloadController.model.count
        _statusMessage = qsTr("正在请求日志列表…")
        _requestTimeout.restart()
        logDownloadController.refresh()
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    RowLayout {
        anchors.fill:   parent
        anchors.margins: _margins
        spacing:        _margins

        // ---- Left: Onboard Logs (板载日志) ----
        Rectangle {
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            color:              qgcPal.window
            radius:             4

            ColumnLayout {
                anchors.fill:       parent
                anchors.margins:    _margins
                spacing:            _margins

                QGCLabel {
                    text:           qsTr("板载日志")
                    font.pointSize: ScreenTools.largeFontPointSize
                    font.bold:      true
                }

                QGCLabel {
                    text:           qsTr("从飞控存储中下载二进制日志文件")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                }

                // Log list header
                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            _margins

                    QGCLabel { text: qsTr("选择"); Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 6 }
                    QGCLabel { text: qsTr("ID");   Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 6 }
                    QGCLabel { text: qsTr("日期"); Layout.fillWidth: true }
                    QGCLabel { text: qsTr("大小"); Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10 }
                    QGCLabel { text: qsTr("状态"); Layout.preferredWidth: ScreenTools.defaultFontPixelWidth * 10 }
                }

                Item {
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true

                    Rectangle {
                        anchors.fill:   parent
                        color:          qgcPal.text
                        opacity:        0.05
                        radius:         2
                    }

                    QGCFlickable {
                        id:             onboardLogFlickable
                        anchors.fill:   parent
                        anchors.margins: 2
                        contentHeight:  onboardLogColumn.height
                        clip:           true

                        Column {
                            id:     onboardLogColumn
                            width:  parent.width

                            Repeater {
                                model: logDownloadController.model

                                delegate: RowLayout {
                                    width:      onboardLogColumn.width
                                    spacing:    _margins
                                    height:     ScreenTools.defaultFontPixelHeight * 1.5

                                    QGCCheckBox {
                                        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 6
                                        checked:                object.selected
                                        onClicked:              object.selected = !object.selected
                                    }

                                    QGCLabel {
                                        text:                   object.id
                                        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 6
                                    }

                                    QGCLabel {
                                        Layout.fillWidth:       true
                                        text: {
                                            if (!object.received) return ""
                                            if (object.time.getUTCFullYear() < 2010) return qsTr("日期未知")
                                            return object.time.toLocaleString(undefined)
                                        }
                                    }

                                    QGCLabel {
                                        text:                   object.sizeStr
                                        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                                    }

                                    QGCLabel {
                                        text:                   object.status
                                        Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 10
                                    }
                                }
                            }
                        }
                    }

                    // Status overlay: visible when no vehicle or status message active
                    QGCLabel {
                        anchors.centerIn:   parent
                        visible:            !_hasVehicle || _statusMessage !== "" || (logDownloadController.model.count === 0 && _hasVehicle && _statusMessage === "")
                        text:               !_hasVehicle ? qsTr("请先连接飞控")
                                                          : (_statusMessage !== "" ? _statusMessage : qsTr("点击刷新获取日志列表"))
                        font.pointSize:     ScreenTools.defaultFontPointSize
                        color:              !_hasVehicle ? "#AAAAAA" : qgcPal.colorGreen
                    }
                }

                // Onboard log buttons
                RowLayout {
                    Layout.fillWidth:   true
                    spacing:            _margins

                    QGCButton {
                        text:       qsTr("刷新")
                        enabled:    _hasVehicle && !logDownloadController.requestingList && !logDownloadController.downloadingLogs
                        onClicked:  _doRefresh()
                    }

                    QGCButton {
                        text:       qsTr("下载")
                        enabled:    _hasVehicle && !logDownloadController.requestingList && !logDownloadController.downloadingLogs
                        onClicked: {
                            if (!_hasVehicle) {
                                noVehicleDialog.open()
                                return
                            }

                            var hasSelected = false
                            for (var i = 0; i < logDownloadController.model.count; i++) {
                                if (logDownloadController.model.get(i).selected) {
                                    hasSelected = true
                                    break
                                }
                            }
                            if (!hasSelected) {
                                noSelectionDialog.open()
                                return
                            }
                            if (ScreenTools.isMobile) {
                                logDownloadController.download()
                            } else {
                                fileDialog.title = qsTr("选择保存目录")
                                fileDialog.folder = QGroundControl.settingsManager.appSettings.logSavePath
                                fileDialog.selectFolder = true
                                fileDialog.openForLoad()
                            }
                        }

                        QGCFileDialog {
                            id: fileDialog
                            onAcceptedForLoad: (file) => {
                                logDownloadController.download(file)
                                close()
                            }
                        }
                    }

                    QGCButton {
                        text:       qsTr("擦除全部")
                        enabled:    _hasVehicle && !logDownloadController.requestingList && !logDownloadController.downloadingLogs && logDownloadController.model.count > 0
                        onClicked:  confirmEraseDialog.open()
                    }

                    QGCButton {
                        text:       qsTr("取消")
                        enabled:    logDownloadController.requestingList || logDownloadController.downloadingLogs
                        onClicked:  logDownloadController.cancel()
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        // ---- Right: Telemetry Logs (遥测日志) ----
        Rectangle {
            Layout.fillWidth:   true
            Layout.fillHeight:  true
            color:              qgcPal.window
            radius:             4

            ColumnLayout {
                anchors.fill:       parent
                anchors.margins:    _margins
                spacing:            _margins

                QGCLabel {
                    text:           qsTr("遥测日志")
                    font.pointSize: ScreenTools.largeFontPointSize
                    font.bold:      true
                }

                QGCLabel {
                    text:           qsTr("实时记录所有 MAVLink 消息到 CSV 文件（每次连接自动创建新文件）")
                    font.pointSize: ScreenTools.smallFontPointSize
                    color:          "#AAAAAA"
                    wrapMode:       Text.WordWrap
                    Layout.fillWidth: true
                }

                // Status info
                ColumnLayout {
                    Layout.fillWidth:   true
                    spacing:            _margins * 0.5

                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            _margins

                        QGCLabel {
                            text:       qsTr("状态：")
                            font.bold:  true
                        }
                        QGCLabel {
                            text:       _hasVehicle && _activeVehicle.mavlinkCsvLogActive ? qsTr("正在记录") : qsTr("未连接")
                            color:      _hasVehicle && _activeVehicle.mavlinkCsvLogActive ? qgcPal.colorGreen : "#AAAAAA"
                        }
                    }

                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            _margins
                        visible:            _hasVehicle && _activeVehicle.mavlinkCsvLogActive

                        QGCLabel {
                            text:       qsTr("文件：")
                            font.bold:  true
                        }
                        QGCLabel {
                            text:       _activeVehicle ? _activeVehicle.mavlinkCsvLogFileName : ""
                            elide:      Text.ElideMiddle
                            Layout.fillWidth: true
                        }
                    }

                    RowLayout {
                        Layout.fillWidth:   true
                        spacing:            _margins
                        visible:            _hasVehicle && _activeVehicle.mavlinkCsvLogActive

                        QGCLabel {
                            text:       qsTr("消息数：")
                            font.bold:  true
                        }
                        QGCLabel {
                            text:       _activeVehicle ? _activeVehicle.mavlinkCsvLogMsgCount.toLocaleString() : "0"
                        }
                    }
                }

                // Supported message types info
                Rectangle {
                    Layout.fillWidth:   true
                    Layout.fillHeight:  true
                    color:              qgcPal.text
                    opacity:            0.05
                    radius:             2

                    QGCFlickable {
                        anchors.fill:       parent
                        anchors.margins:    _margins
                        contentHeight:      msgTypeInfo.height
                        clip:               true

                        ColumnLayout {
                            id:     msgTypeInfo
                            width:  parent.width
                            spacing: _margins * 0.5

                            QGCLabel {
                                text:       qsTr("记录的 MAVLink 消息类型：")
                                font.bold:  true
                            }

                            QGCLabel { text: "HEARTBEAT (0) - " + qsTr("心跳、飞行模式、解锁状态") }
                            QGCLabel { text: "SYS_STATUS (1) - " + qsTr("电压、电流、电池剩余") }
                            QGCLabel { text: "GPS_RAW_INT (24) - " + qsTr("GPS定位、经纬度、卫星数") }
                            QGCLabel { text: "SCALED_PRESSURE (29) - " + qsTr("气压、温度") }
                            QGCLabel { text: "ATTITUDE (30) - " + qsTr("横滚、俯仰、偏航") }
                            QGCLabel { text: "GLOBAL_POSITION_INT (33) - " + qsTr("全局位置、速度、航向") }
                            QGCLabel { text: "VFR_HUD (74) - " + qsTr("空速、地速、高度、爬升率") }
                            QGCLabel { text: "BATTERY_STATUS (147) - " + qsTr("电池温度、电压、消耗") }
                            QGCLabel {
                                text:       qsTr("其他消息 - 仅记录消息ID和名称")
                                color:      "#AAAAAA"
                            }
                        }
                    }
                }
            }
        }
    }

    // Dialogs - use MessageDialog like other BasicMode views
    MessageDialog {
        id:         noSelectionDialog
        title:      qsTr("日志下载")
        text:       qsTr("请至少选择一个日志文件进行下载。")
        buttons:    MessageDialog.Ok
    }

    MessageDialog {
        id:         noVehicleDialog
        title:      qsTr("日志下载")
        text:       qsTr("请先连接飞行器，再执行日志下载操作。")
        buttons:    MessageDialog.Ok
    }

    MessageDialog {
        id:         confirmEraseDialog
        title:      qsTr("删除全部日志")
        text:       qsTr("所有日志文件将被永久删除。确定要继续吗？")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                logDownloadController.eraseAll()
            }
        }
    }

    function _formatSize(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }
}
