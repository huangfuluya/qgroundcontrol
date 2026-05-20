/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// Basic Mode - Three-tab simplified interface for non-technical operators
// Tab 1: 实时状态 (Real-time Status)
// Tab 2: 视频监控 (Video Monitor)
// Tab 3: 航点规划 (Waypoint Planning)

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.ScreenTools

Item {
    id: _root

    property var    _activeVehicle:     QGroundControl.multiVehicleManager.activeVehicle
    property var    planControllerFlyView:   basicFlyView.planController
    property var    guidedControllerFlyView: basicFlyView.guidedController

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // Top Tab Bar - full width
        QGCTabBar {
            id:                 basicModeTabBar
            Layout.fillWidth:   true
            Layout.preferredHeight: ScreenTools.toolbarHeight

            Component.onCompleted: currentIndex = 0

            QGCTabButton {
                text:       qsTr("实时状态")
                pointSize:  ScreenTools.largeFontPointSize
            }
            QGCTabButton {
                text:       qsTr("视频监控")
                pointSize:  ScreenTools.largeFontPointSize
            }
            QGCTabButton {
                text:       qsTr("航点规划")
                pointSize:  ScreenTools.largeFontPointSize
            }
            QGCTabButton {
                text:       qsTr("日志下载")
                pointSize:  ScreenTools.largeFontPointSize
            }
        }

        // Tab content area
        Item {
            Layout.fillWidth:   true
            Layout.fillHeight:  true

            // Tab 1: Real-time Status
            BasicFlyView {
                id:             basicFlyView
                anchors.fill:   parent
                visible:        basicModeTabBar.currentIndex === 0
            }

            // Tab 2: Video Monitor
            BasicVideoView {
                anchors.fill:   parent
                visible:        basicModeTabBar.currentIndex === 1
            }

            // Tab 3: Waypoint Planning
            BasicPlanView {
                anchors.fill:   parent
                visible:        basicModeTabBar.currentIndex === 2
            }

            // Tab 4: Log Download
            BasicLogDownloadView {
                anchors.fill:   parent
                visible:        basicModeTabBar.currentIndex === 3
            }
        }
    }
}