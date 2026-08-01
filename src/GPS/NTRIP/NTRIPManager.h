/****************************************************************************
 *
 * (c) 2009-2024 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/

#pragma once

#include <QtCore/QLoggingCategory>
#include <QtCore/QObject>
#include <QtCore/QString>
#include <QtCore/QTimer>

Q_DECLARE_LOGGING_CATEGORY(NTRIPManagerLog)

class NtripTcpClient;
class RTCMMavlink;

/// Receives RTCM correction data from an NTRIP caster over the network and
/// forwards it to all connected vehicles as GPS_RTCM_DATA mavlink messages.
/// Periodically reports the GCS/vehicle position to the caster as NMEA GGA.
class NTRIPManager : public QObject
{
    Q_OBJECT

    Q_PROPERTY(QString ntripStatus   READ ntripStatus   NOTIFY ntripStatusChanged)
    Q_PROPERTY(bool    connected     READ connected     NOTIFY connectedChanged)

public:
    explicit NTRIPManager(QObject *parent = nullptr);
    ~NTRIPManager();

    QString ntripStatus() const { return _ntripStatus; }
    bool connected() const;

signals:
    void ntripStatusChanged();
    void connectedChanged();

private slots:
    void _onConnectEnabledChanged();
    void _onConnectionSettingsChanged();
    void _onConnected();
    void _onDisconnected();
    void _onError(const QString &message);
    void _sendGGA();

private:
    void _start();
    void _stop();
    void _setStatus(const QString &status);
    void _setConnected(bool connected);
    QByteArray _buildGGA() const;

    NtripTcpClient *_client = nullptr;
    RTCMMavlink *_rtcmMavlink = nullptr;
    QTimer *_ggaTimer = nullptr;
    QTimer *_reconnectTimer = nullptr;
    QString _ntripStatus;
    bool _connected = false;

    static constexpr int kGGAIntervalMSecs = 10000;
    static constexpr int kReconnectIntervalMSecs = 5000;
};
