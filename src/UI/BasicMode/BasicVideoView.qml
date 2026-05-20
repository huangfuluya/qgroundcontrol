/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// 视频监控 - Video Monitor Tab
// Video feed occupies 90% of space
// Top-right: camera switch button (multi-camera)
// Bottom-right: Start Recording + Take Photo buttons

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Palette
import QGroundControl.ScreenTools

Item {
    id: _root

    property bool _recording: false
    property real _margins:   ScreenTools.defaultFontPixelWidth

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    Rectangle {
        anchors.fill:   parent
        color:          "black"

        // Video placeholder / background
        QGCLabel {
            anchors.centerIn:   parent
            text:               qsTr("视频画面区域\n等待视频信号...")
            font.pointSize:     ScreenTools.largeFontPointSize * 2
            color:              "#555555"
            horizontalAlignment: Text.AlignHCenter
            visible:            !QGroundControl.videoManager.hasVideo
        }

        // The actual video would display here when video manager has video
        // For QGC's architecture, video is typically managed by FlyViewVideo
        // Basic mode overlay: just show recording/photo controls
    }

    //-- Camera Switch Button (top-right)
    QGCButton {
        anchors.top:        parent.top
        anchors.right:      parent.right
        anchors.margins:    _margins * 2
        text:               qsTr("切换摄像头")
        font.pointSize:     ScreenTools.largeFontPointSize
        visible:            QGroundControl.videoManager.hasVideo
        onClicked: {
            // Switch to next camera
            QGroundControl.videoManager.nextStream()
        }
    }

    //-- Bottom-right controls
    RowLayout {
        anchors.bottom:     parent.bottom
        anchors.right:      parent.right
        anchors.margins:    _margins * 3
        spacing:            _margins * 2

        // Start/Stop Recording
        QGCButton {
            text:               _recording ? qsTr("停止录像") : qsTr("开始录像")
            font.pointSize:     ScreenTools.largeFontPointSize
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 18
            enabled:            QGroundControl.videoManager.hasVideo
            backgroundColor:    _recording ? "#FF4444" : qgcPal.primaryButton
            onClicked: {
                if (_recording) {
                    QGroundControl.videoManager.stopRecording()
                } else {
                    QGroundControl.videoManager.startRecording()
                }
                _recording = !_recording
            }
        }

        // Take Photo
        QGCButton {
            text:               qsTr("拍照")
            font.pointSize:     ScreenTools.largeFontPointSize
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 18
            enabled:            QGroundControl.videoManager.hasVideo
            onClicked: {
                QGroundControl.videoManager.takePhoto()
            }
        }
    }
}