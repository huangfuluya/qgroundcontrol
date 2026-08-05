/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

// Video Monitor - Full-screen video with on-screen gimbal controls
// Bottom-right: Record + Photo

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls
import QGroundControl.Controllers
import QGroundControl.Palette
import QGroundControl.ScreenTools

Item {
    id: _root

    property bool _recording: false
    property real _margins:   ScreenTools.defaultFontPixelWidth
    property int  _track_rec_x: 0
    property int  _track_rec_y: 0
    property bool _showingSecondVideo: false

    QGCPalette { id: qgcPal; colorGroupEnabled: true }

    //-- First Video
    FlightDisplayViewVideo {
        id:             videoStreaming
        anchors.fill:   parent
        useSmallFont:   false
        visible:        !_showingSecondVideo
    }

    //-- Second Video overlay
    Rectangle {
        id:             secondVideoOverlay
        anchors.fill:   parent
        color:          "black"
        visible:        QGroundControl.videoManager.hasVideo2 && _showingSecondVideo

        QGCVideoBackground {
            id:             secondVideoDisplay
            objectName:     "secondVideoContent"
            anchors.fill:   parent
        }

        QGCLabel {
            text:           qsTr("WAITING FOR SECOND VIDEO")
            font.bold:      true
            color:          "white"
            font.pointSize: ScreenTools.smallFontPointSize
            anchors.centerIn: parent
            visible:        !QGroundControl.videoManager.decoding2
        }
    }

    //-- On-Screen Gimbal Controller
    OnScreenGimbalController {
        id:                      onScreenGimbalController
        anchors.fill:            parent
        screenX:                 videoMouseArea.mouseX
        screenY:                 videoMouseArea.mouseY
        cameraTrackingEnabled:   videoStreaming._camera && videoStreaming._camera.trackingEnabled
    }

    //-- MouseArea for gimbal + tracking ROI
    MouseArea {
        id:                         videoMouseArea
        anchors.fill:               parent
        hoverEnabled:               true

        property double x0:         0
        property double x1:         0
        property double y0:         0
        property double y1:         0
        property double offset_x:   0
        property double offset_y:   0
        property double radius:     20
        property var trackingROI:   null
        property var trackingStatus: trackingStatusComponent.createObject(videoMouseArea, {})

        onClicked:       onScreenGimbalController.clickControl()

        onPressed:(mouse) => {
            onScreenGimbalController.pressControl()
            _track_rec_x = mouse.x
            _track_rec_y = mouse.y
            if(videoStreaming._camera) {
                if (videoStreaming._camera.trackingEnabled) {
                    trackingROI = trackingROIComponent.createObject(videoMouseArea, {"x": mouse.x, "y": mouse.y})
                }
            }
        }
        onPositionChanged: (mouse) => {
            if (trackingROI !== null) {
                if (mouse.x < trackingROI.x) {
                    trackingROI.x = mouse.x
                    trackingROI.width = Math.abs(mouse.x - _track_rec_x)
                } else {
                    trackingROI.width = Math.abs(mouse.x - trackingROI.x)
                }
                if (mouse.y < trackingROI.y) {
                    trackingROI.y = mouse.y
                    trackingROI.height = Math.abs(mouse.y - _track_rec_y)
                } else {
                    trackingROI.height = Math.abs(mouse.y - trackingROI.y)
                }
            }
        }
        onReleased: (mouse) => {
            onScreenGimbalController.releaseControl()
            if (trackingROI !== null) {
                trackingROI.destroy()
                trackingROI = null
            }
            if(videoStreaming._camera) {
                if (videoStreaming._camera.trackingEnabled) {
                    x0 = Math.min(_track_rec_x, mouse.x)
                    x1 = Math.max(_track_rec_x, mouse.x)
                    y0 = Math.min(_track_rec_y, mouse.y)
                    y1 = Math.max(_track_rec_y, mouse.y)
                    offset_x = (parent.width - videoStreaming.getWidth()) / 2
                    offset_y = (parent.height - videoStreaming.getHeight()) / 2
                    x0 = x0 - offset_x
                    x1 = x1 - offset_x
                    y0 = y0 - offset_y
                    y1 = y1 - offset_y
                    x0 = Math.max(Math.min(x0 / videoStreaming.getWidth(), 1.0), 0.0)
                    x1 = Math.max(Math.min(x1 / videoStreaming.getWidth(), 1.0), 0.0)
                    y0 = Math.max(Math.min(y0 / videoStreaming.getHeight(), 1.0), 0.0)
                    y1 = Math.max(Math.min(y1 / videoStreaming.getHeight(), 1.0), 0.0)
                    if (Math.abs(_track_rec_x - mouse.x) < 10 && Math.abs(_track_rec_y - mouse.y) < 10) {
                        var pt  = Qt.point(x0, y0)
                        videoStreaming._camera.startTracking(pt, radius / videoStreaming.getWidth())
                    } else {
                        var rec = Qt.rect(x0, y0, x1 - x0, y1 - y0)
                        videoStreaming._camera.startTracking(rec)
                    }
                    _track_rec_x = 0
                    _track_rec_y = 0
                }
            }
        }

        Component {
            id: trackingROIComponent
            Rectangle {
                color:              Qt.rgba(0.1,0.85,0.1,0.25)
                border.color:       "green"
                border.width:       1
            }
        }

        Component {
            id: trackingStatusComponent
            Rectangle {
                color:              "transparent"
                border.color:       "red"
                border.width:       5
                radius:             5
            }
        }

        Timer {
            id: trackingStatusTimer
            interval:               50
            repeat:                 true
            running:                true
            onTriggered: {
                if (videoStreaming._camera) {
                    if (videoStreaming._camera.trackingEnabled && videoStreaming._camera.trackingImageStatus) {
                        var margin_hor = (parent.parent.width - videoStreaming.getWidth()) / 2
                        var margin_ver = (parent.parent.height - videoStreaming.getHeight()) / 2
                        var left = margin_hor + videoStreaming.getWidth() * videoStreaming._camera.trackingImageRect.left
                        var top = margin_ver + videoStreaming.getHeight() * videoStreaming._camera.trackingImageRect.top
                        var right = margin_hor + videoStreaming.getWidth() * videoStreaming._camera.trackingImageRect.right
                        var bottom = margin_ver + !isNaN(videoStreaming._camera.trackingImageRect.bottom) ? videoStreaming.getHeight() * videoStreaming._camera.trackingImageRect.bottom : top + (right - left)
                        var width = right - left
                        var height = bottom - top
                        videoMouseArea.trackingStatus.x = left
                        videoMouseArea.trackingStatus.y = top
                        videoMouseArea.trackingStatus.width = width
                        videoMouseArea.trackingStatus.height = height
                    } else {
                        videoMouseArea.trackingStatus.x = 0
                        videoMouseArea.trackingStatus.y = 0
                        videoMouseArea.trackingStatus.width = 0
                        videoMouseArea.trackingStatus.height = 0
                    }
                }
            }
        }
    }

    //-- Bottom-right controls
    RowLayout {
        anchors.bottom:     parent.bottom
        anchors.right:      parent.right
        anchors.margins:    _margins * 3
        spacing:            _margins * 2
        z:                  QGroundControl.zOrderWidgets

        QGCButton {
            text:               _recording ? qsTr("Stop Recording") : qsTr("Start Recording")
            font.pointSize:     ScreenTools.largeFontPointSize
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 18
            enabled:            QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.hasVideo2
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

        QGCButton {
            text:               qsTr("Take Photo")
            font.pointSize:     ScreenTools.largeFontPointSize
            Layout.preferredHeight: ScreenTools.defaultFontPixelHeight * 3
            Layout.preferredWidth:  ScreenTools.defaultFontPixelWidth * 18
            enabled:            QGroundControl.videoManager.hasVideo || QGroundControl.videoManager.hasVideo2
            onClicked: {
                QGroundControl.videoManager.grabImage()
            }
        }
    }
}
