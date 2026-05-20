/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// 航点规划 - Waypoint Planning Tab
// Simplified plan view with map and essential toolbar
// Left toolbar: Add Waypoint, Delete Waypoint, Clear Mission, Start Mission, Pause Mission
// Mission progress display at bottom

import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtLocation
import QtPositioning

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlightDisplay
import QGroundControl.FlightMap
import QGroundControl.Palette
import QGroundControl.ScreenTools
import QGroundControl.Controllers

Item {
    id: _root

    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     planMasterController.missionController
    property real   _margins:               ScreenTools.defaultFontPixelWidth
    property bool   _missionRunning:        false

    readonly property var _defaultVehicleCoordinate:  QtPositioning.coordinate(37.803784, -122.462276)

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    PlanMasterController {
        id:         planMasterController
        flyView:    false

        Component.onCompleted: {
            planMasterController.start()
            if (_missionController) {
                _missionController.setCurrentPlanViewSeqNum(0, true)
            }
        }

        function upload() {
            if (_activeVehicle) {
                planMasterController.sendToVehicle()
                _missionRunning = true
            }
        }
    }

    // Left toolbar
    Rectangle {
        id:                 leftToolbar
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.bottom:     parent.bottom
        anchors.margins:    _margins
        width:              ScreenTools.defaultFontPixelWidth * 20
        color:              qgcPal.window
        border.color:       qgcPal.windowShadeDark
        radius:             ScreenTools.defaultFontPixelWidth * 0.5

        ColumnLayout {
            anchors.fill:       parent
            anchors.margins:    _margins
            spacing:            _margins

            QGCLabel {
                text:               qsTr("任务工具")
                font.pointSize:     ScreenTools.largeFontPointSize
                font.bold:          true
                Layout.alignment:   Qt.AlignHCenter
            }

            Item { Layout.preferredHeight: _margins }

            // Add Waypoint
            QGCButton {
                Layout.fillWidth:   true
                text:               qsTr("添加航点")
                font.pointSize:     ScreenTools.largeFontPointSize
                enabled:            !_missionRunning
                onClicked: {
                    addWaypointMode = true
                }
            }

            // Delete Waypoint
            QGCButton {
                Layout.fillWidth:   true
                text:               qsTr("删除航点")
                font.pointSize:     ScreenTools.largeFontPointSize
                enabled:            !_missionRunning && _missionController.visualItems.count > 1
                onClicked: {
                    var currentIndex = _missionController.currentPlanViewVIIndex
                    if (currentIndex >= 0 && currentIndex < _missionController.visualItems.count) {
                        _missionController.removeVisualItem(currentIndex)
                    }
                }
            }

            // Clear Mission
            QGCButton {
                Layout.fillWidth:   true
                text:               qsTr("清空任务")
                font.pointSize:     ScreenTools.largeFontPointSize
                enabled:            !_missionRunning && _missionController.visualItems.count > 1
                onClicked: {
                    confirmClearDialog.open()
                }
            }

            Item { Layout.preferredHeight: _margins }

            // Start Mission
            QGCButton {
                Layout.fillWidth:   true
                text:               _missionRunning ? qsTr("执行中...") : qsTr("开始任务")
                font.pointSize:     ScreenTools.largeFontPointSize
                enabled:            !_missionRunning && _missionController.visualItems.count > 1 && _activeVehicle
                backgroundColor:    qgcPal.colorGreen
                onClicked: {
                    confirmStartDialog.open()
                }
            }

            // Pause Mission
            QGCButton {
                Layout.fillWidth:   true
                text:               qsTr("暂停任务")
                font.pointSize:     ScreenTools.largeFontPointSize
                enabled:            _missionRunning
                backgroundColor:    "orange"
                onClicked: {
                    if (_activeVehicle) {
                        _activeVehicle.pauseMission()
                        _missionRunning = false
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // Map area
    FlightMap {
        id:                         editorMap
        anchors.left:               leftToolbar.right
        anchors.right:              parent.right
        anchors.top:                parent.top
        anchors.bottom:             missionProgressBar.visible ? missionProgressBar.top : parent.bottom
        anchors.margins:            _margins
        mapName:                    "BasicModeMissionEditor"
        allowGCSLocationCenter:     true
        allowVehicleLocationCenter: true
        planView:                   true

        zoomLevel:                  QGroundControl.flightMapZoom
        center:                     QGroundControl.flightMapPosition

        onMapClicked: (mouse) => {
            var coordinate = editorMap.toCoordinate(Qt.point(mouse.x, mouse.y), false)
            coordinate.latitude = coordinate.latitude.toFixed(8)
            coordinate.longitude = coordinate.longitude.toFixed(8)
            var nextIndex = _missionController.currentPlanViewVIIndex + 1
            _missionController.insertSimpleMissionItem(coordinate, nextIndex, true)
        }

        // Mission item visuals
        Repeater {
            model: _missionController.visualItems
            delegate: MissionItemMapVisual {
                map:         editorMap
                opacity:     1
                interactive: true
                vehicle:     planMasterController.controllerVehicle
                onClicked:   (sequenceNumber) => { _missionController.setCurrentPlanViewSeqNum(sequenceNumber, false) }
            }
        }

        // Mission lines
        MissionLineView {
            model:              _missionController.simpleFlightPathSegments
            opacity:            1
        }

        // Vehicle on map
        MapItemView {
            model: QGroundControl.multiVehicleManager.vehicles
            delegate: VehicleMapItem {
                vehicle:        object
                coordinate:     object.coordinate
                map:            editorMap
                size:           ScreenTools.defaultFontPixelHeight * 3
                z:              QGroundControl.zOrderMapItems - 1
            }
        }
    }

    // Mission progress bar
    Rectangle {
        id:                 missionProgressBar
        anchors.left:       leftToolbar.right
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.margins:    _margins
        height:             ScreenTools.defaultFontPixelHeight * 4
        color:              qgcPal.toolbarBackground
        visible:            _missionRunning

        RowLayout {
            anchors.fill:       parent
            anchors.margins:    _margins

            QGCLabel {
                text:           qsTr("任务进度:")
                font.pointSize: ScreenTools.largeFontPointSize
            }

            Rectangle {
                Layout.fillWidth:   true
                Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 1.5
                radius:             3
                color:              qgcPal.button

                Rectangle {
                    anchors.left:   parent.left
                    anchors.top:    parent.top
                    anchors.bottom: parent.bottom
                    width:          parent.width * 0.3
                    radius:         3
                    color:          qgcPal.colorGreen
                }
            }

            QGCLabel {
                text:           qsTr("进行中")
                font.pointSize: ScreenTools.defaultFontPointSize
                color:          qgcPal.colorGreen
            }
        }
    }

    //-- Confirmation Dialogs
    MessageDialog {
        id:         confirmStartDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要开始执行任务吗？\n无人船将按照规划的航点顺序自动航行。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                planMasterController.upload()
            }
        }
    }

    MessageDialog {
        id:         confirmClearDialog
        title:      qsTr("确认操作")
        text:       qsTr("确定要清空所有航点吗？\n此操作不可撤销。")
        buttons:    MessageDialog.Yes | MessageDialog.No
        onButtonClicked: function (button, role) {
            if (button === MessageDialog.Yes) {
                _missionController.removeAll()
                _missionController.insertSimpleMissionItem(mapCenter(), 0, true)
            }
        }
    }

    function mapCenter() {
        var coordinate = editorMap.center
        coordinate.latitude  = coordinate.latitude.toFixed(8)
        coordinate.longitude = coordinate.longitude.toFixed(8)
        coordinate.altitude  = coordinate.altitude.toFixed(8)
        return coordinate
    }
}